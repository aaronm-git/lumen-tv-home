package local.tvhome;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.crypto.Cipher;
import javax.crypto.KeyAgreement;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Your T3 Code chats, from the Lumen Agents helper on the Mac (see mac/). Lumen finds it with Bonjour and pairs
 * once with a code shown on the TV. Then it keeps one request open that the Mac answers as soon as a chat changes,
 * but only while the home screen is showing, or while notifications are on and the TV is awake. Requests are
 * signed and replies encrypted with the paired key, so other devices on the network can't read or fake them.
 * Once paired, nothing unsealed changes anything: only "Pair again" in Settings forgets the key.
 */
final class AgentStatus {
    static final int SEARCHING = 0, OFFLINE = 1, PAIRING = 2, READY = 3;
    private static final String SERVICE = "_lumen-agents._tcp";
    private static final long POLL_MS = 4000, RETRY_MS = 10_000, SEARCH_MS = 8000;
    /** The pairing scheme a key was made with; keys from older ones (six-digit codes) are dropped. */
    private static final int SCHEME = 2;
    /** Who wants updates: the home screen and/or notifications. */
    static final String HOME = "home", NOTIFY = "notify";
    private static AgentStatus instance;

    interface Listener {
        void onAgents(Snapshot s);
    }

    static final class Chat {
        final String id, title, project, state, detail, text;
        /** claude, openai, grok, gemini, cursor or opencode (for the icon), and the model's own name. */
        final String brand, model;
        /** Seconds since it started, asked or finished, as of the reply. */
        final long age;

        Chat(JSONObject o) {
            id = o.optString("id");
            title = o.optString("title", "Untitled");
            project = o.optString("project");
            state = o.optString("state", "working");
            detail = o.optString("detail");
            text = o.optString("text", null);
            age = o.optLong("age", -1);
            brand = o.optString("brand");
            model = o.optString("model");
        }
    }

    static final class Snapshot {
        final int phase;
        /** The Mac's name, the pairing code, and T3 Code's state on the Mac ("ok" when it's running). */
        final String mac, code, t3;
        final List<Chat> chats;

        boolean active() {
            return phase == READY && "ok".equals(t3);
        }

        Snapshot(int phase, String mac, String code, String t3, List<Chat> chats) {
            this.phase = phase;
            this.mac = mac;
            this.code = code;
            this.t3 = t3;
            this.chats = chats;
        }
    }

    private final Context app;
    private final SharedPreferences sp;
    private final List<Listener> listeners = new ArrayList<>();
    private final Set<String> wanted = new HashSet<>();
    private final Handler main = new Handler(Looper.getMainLooper());
    /** Started once and kept, so the work below never runs on two threads at once. */
    private HandlerThread thread;
    /**
     * Set while running, and new each start and each Pair again: work and replies for an older one are dropped, so a
     * request still on its way when we stopped can't show its chats later. Everything below is only touched on the
     * thread.
     */
    private volatile Handler worker;
    private NsdManager.DiscoveryListener discovery;
    private boolean resolving;
    private long searchingSince;
    private int failures;
    /** The Mac's version of the chats we last saw; the next request waits for it to change. */
    private long version = -1;
    private volatile HttpURLConnection waiting;
    Snapshot last;

    static AgentStatus get(Context c) {
        if (instance == null) instance = new AgentStatus(c.getApplicationContext());
        return instance;
    }

    private AgentStatus(Context c) {
        app = c;
        sp = app.getSharedPreferences("agents", Context.MODE_PRIVATE);
    }

    /** Main thread. A new listener hears the latest snapshot at once. */
    void addListener(Listener l) {
        listeners.add(l);
        if (last != null) l.onAgents(last);
    }

    void removeListener(Listener l) {
        listeners.remove(l);
    }

    /** Main thread. Runs while anyone wants it. */
    void want(String who, boolean on) {
        if (on) wanted.add(who);
        else wanted.remove(who);
        if (wanted.isEmpty()) stop();
        else start();
    }

    private void start() {
        if (worker != null) return;
        if (thread == null) {
            thread = new HandlerThread("agents");
            thread.start();
        }
        Handler w = new Handler(thread.getLooper());
        worker = w;
        w.post(() -> {
            // Ask for the current chats at once rather than waiting for a change since we stopped.
            version = -1;
            poll(w);
        });
    }

    private void stop() {
        Handler w = worker;
        if (w == null) return;
        worker = null;
        w.removeCallbacksAndMessages(null);
        new Handler(thread.getLooper()).post(this::stopDiscovery);
        // Not kept while nobody listens: whatever comes next must be current, not chats from before.
        last = null;
        letGo();
    }

    /** Lets go of a request the Mac is holding open (closing it is network work, so not on this thread). */
    private void letGo() {
        HttpURLConnection c = waiting;
        if (c != null) new Thread(c::disconnect).start();
    }

    boolean paired() {
        return sp.getBoolean("paired", false);
    }

    /**
     * Main thread. Settings: Pair again. Forgets the key, here and (if it can reach it) on the Mac, so the next
     * request pairs with a new code.
     */
    void pairAgain() {
        Handler old = worker;
        if (old == null) {
            String host = sp.getString("host", null), device = sp.getString("device", null);
            String key = sp.getString("key", null);
            forget();
            new Thread(() -> revoke(host, device, key)).start();
            return;
        }
        // A new worker, so a reply to a request made with the old key isn't shown after this.
        old.removeCallbacksAndMessages(null);
        Handler w = new Handler(thread.getLooper());
        worker = w;
        w.post(() -> {
            if (w != worker) return;
            String host = sp.getString("host", null), device = sp.getString("device", null);
            String key = sp.getString("key", null);
            forget();
            revoke(host, device, key);
            failures = 0;
            poll(w);
        });
        letGo();
    }

    private void forget() {
        sp.edit().remove("key").remove("scheme").remove("code").remove("device").putBoolean("paired", false).apply();
        version = -1;
    }

    /**
     * Best effort: asks the Mac to drop the key it keeps for this TV, with a request signed by that key (so nobody
     * else can). If the Mac can't be reached, `lumen-agents unpair` there removes it.
     */
    private static void revoke(String host, String device, String key) {
        if (host == null || device == null || key == null) return;
        try {
            byte[] k = Base64.decode(key, Base64.NO_WRAP);
            if (k.length != 32) return;
            String time = String.valueOf(System.currentTimeMillis());
            HttpURLConnection c = open(host, "/forget");
            try {
                c.setRequestMethod("POST");
                c.setRequestProperty("X-Lumen-Device", device);
                c.setRequestProperty("X-Lumen-Time", time);
                c.setRequestProperty("X-Lumen-Auth",
                        hex(hmac(k, ("POST /forget\n" + time).getBytes(StandardCharsets.UTF_8))));
                c.setDoOutput(true);
                c.setFixedLengthStreamingMode(0);
                c.getOutputStream().close();
                c.getResponseCode();
            } finally {
                c.disconnect();
            }
        } catch (IOException | GeneralSecurityException | RuntimeException ignored) {
            // Pair again anyway.
        }
    }

    /** The code as the TV shows it: K7QM-9XRT-4HNP-2WVD. */
    static String grouped(String code) {
        if (code == null) return "";
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < code.length(); i++) {
            if (i > 0 && i % 4 == 0) b.append('-');
            b.append(code.charAt(i));
        }
        return b.toString();
    }

    private void poll(Handler w) {
        if (w != worker) return;
        // A key from an older pairing scheme: the Mac no longer accepts it, so start over.
        if (sp.getString("key", null) != null && sp.getInt("scheme", 0) != SCHEME) forget();
        long next = POLL_MS;
        String host = sp.getString("host", null);
        try {
            if (host == null) {
                next = RETRY_MS;
                search(w);
            } else if (sp.getString("key", null) == null) {
                pair(w, host);
            } else {
                next = status(w, host);
            }
        } catch (IOException | JSONException | GeneralSecurityException | RuntimeException e) {
            // Stopped or Pair again meanwhile: whatever went wrong belongs to that older worker.
            if (w != worker) return;
            // The Mac may be asleep or have a new address: look for it again, but keep trying the old one.
            // (RuntimeException: whatever arrives, from a spoofed helper too, mustn't crash the launcher.)
            version = -1;
            ++failures;
            if (failures >= 2) search(w);
            // Once paired, chats we can't confirm aren't shown: the first failure clears them. Before that a
            // second try keeps a hiccup from interrupting the code on screen.
            if (failures >= 2 || paired()) {
                publish(w, new Snapshot(OFFLINE, sp.getString("mac", "Mac"), null, null, Collections.emptyList()));
            }
            next = failures >= 2 ? RETRY_MS : POLL_MS;
        }
        if (w == worker) w.postDelayed(() -> poll(w), next);
    }

    /** Returns how long to wait before asking again. */
    private long status(Handler w, String host) throws IOException, JSONException, GeneralSecurityException {
        byte[] key = Base64.decode(sp.getString("key", ""), Base64.NO_WRAP);
        if (key.length != 32) throw new GeneralSecurityException("bad key");
        String time = String.valueOf(System.currentTimeMillis());
        long asked = SystemClock.elapsedRealtime();
        String target = version >= 0 ? "/status?wait=" + version : "/status";
        HttpURLConnection c = open(host, target);
        // The Mac holds a waiting reply for 45 s, up to 55 s by its 10 s tick, when nothing has changed. A Mac that
        // goes silent (asleep, off the network) is noticed when this runs out, so the chats on screen are at most
        // about a minute old; the first failure clears them (poll). An asking-at-once request keeps open()'s 4 s.
        if (version >= 0) c.setReadTimeout(60_000);
        waiting = c;
        try {
            c.setRequestProperty("X-Lumen-Device", sp.getString("device", ""));
            c.setRequestProperty("X-Lumen-Time", time);
            c.setRequestProperty("X-Lumen-Auth",
                    hex(hmac(key, ("GET " + target + "\n" + time).getBytes(StandardCharsets.UTF_8))));
            int code = c.getResponseCode();
            byte[] box = readAll(code >= 400 ? c.getErrorStream() : c.getInputStream());
            // Stopped or Pair again while this was on its way: it changes nothing and isn't shown.
            if (w != worker) return POLL_MS;
            if ((code == 401 || code == 403) && !paired()) {
                // Not approved yet: the Mac can't seal anything until the code is typed there, so these are plain.
                // Forged ones can only delay pairing.
                failures = 0;
                stopDiscovery();
                if (code == 401) {
                    // The request expired, or the Mac restarted: start over with a new code.
                    forget();
                } else {
                    publish(w, new Snapshot(PAIRING, sp.getString("mac", "Mac"), sp.getString("code", ""), null,
                            Collections.emptyList()));
                }
                return POLL_MS;
            }
            // Anything else is a failure (offline, at once once paired: see poll), never a reason to drop the key:
            // these aren't sealed, so anyone could send them.
            if (code != 200) throw new IOException("HTTP " + code);
            // AES-GCM: nonce, then ciphertext and tag. Anything not sealed with our key fails here.
            if (box.length < 28) throw new IOException("not sealed");
            Cipher aes = Cipher.getInstance("AES/GCM/NoPadding");
            aes.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, box, 0, 12));
            aes.updateAAD(time.getBytes(StandardCharsets.UTF_8));
            byte[] body = aes.doFinal(box, 12, box.length - 12);
            failures = 0;
            stopDiscovery();
            JSONObject o = new JSONObject(new String(body, StandardCharsets.UTF_8));
            List<Chat> chats = new ArrayList<>();
            JSONArray a = o.optJSONArray("chats");
            for (int i = 0; a != null && i < a.length(); i++) chats.add(new Chat(a.getJSONObject(i)));
            String mac = o.optString("mac", "Mac");
            if (!paired() || !mac.equals(sp.getString("mac", null))) {
                sp.edit().putBoolean("paired", true).putString("mac", mac).apply();
            }
            publish(w, new Snapshot(READY, mac, null, o.optString("t3", "ok"), chats));
            long v = o.optLong("version", -1);
            boolean changed = v != version;
            version = v;
            // Straight back to waiting, unless the Mac answered at once without news (an older helper).
            return changed || SystemClock.elapsedRealtime() - asked > 2000 ? 0 : POLL_MS;
        } finally {
            waiting = null;
            c.disconnect();
        }
    }

    /**
     * Agrees a secret with the Mac (P-256 ECDH) and makes a random code that never goes over the network. The key
     * needs both, so only a Mac you typed the code into (lumen-agents pair <code>) can read or sign anything.
     */
    private void pair(Handler w, String host) throws IOException, JSONException, GeneralSecurityException {
        KeyPairGenerator g = KeyPairGenerator.getInstance("EC");
        g.initialize(new ECGenParameterSpec("secp256r1"));
        KeyPair mine = g.generateKeyPair();
        byte[] der = mine.getPublic().getEncoded();
        JSONObject req = new JSONObject()
                .put("key", Base64.encodeToString(der, Base64.NO_WRAP))
                .put("name", Build.MODEL);

        HttpURLConnection c = open(host, "/pair");
        JSONObject reply;
        try {
            c.setRequestMethod("POST");
            c.setDoOutput(true);
            c.setRequestProperty("Content-Type", "application/json");
            try (OutputStream out = c.getOutputStream()) {
                out.write(req.toString().getBytes(StandardCharsets.UTF_8));
            }
            if (c.getResponseCode() != 200) throw new IOException("HTTP " + c.getResponseCode());
            reply = new JSONObject(new String(readAll(c.getInputStream()), StandardCharsets.UTF_8));
        } finally {
            c.disconnect();
        }
        if (w != worker) return;

        byte[] macDer = Base64.decode(reply.getString("key"), Base64.NO_WRAP);
        if (macDer.length > 200) throw new GeneralSecurityException("bad key");
        PublicKey theirs = KeyFactory.getInstance("EC").generatePublic(new X509EncodedKeySpec(macDer));
        KeyAgreement ka = KeyAgreement.getInstance("ECDH");
        ka.init(mine.getPrivate());
        ka.doPhase(theirs, true);
        byte[] secret = ka.generateSecret();
        if (secret.length != 32) throw new GeneralSecurityException("bad secret");
        // 16 characters of Crockford base32: 80 bits, so nobody can guess it to sit in the middle.
        String alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        SecureRandom random = new SecureRandom();
        StringBuilder code = new StringBuilder();
        for (int i = 0; i < 16; i++) code.append(alphabet.charAt(random.nextInt(32)));
        byte[] key = derive("lumen-agents/v2".getBytes(StandardCharsets.UTF_8), secret,
                code.toString().getBytes(StandardCharsets.US_ASCII), der, macDer);
        byte[] id = new byte[8];
        System.arraycopy(sha256(der), 0, id, 0, 8);
        String mac = reply.optString("mac", "Mac");
        if (mac.length() > 60) mac = mac.substring(0, 60);
        sp.edit()
                .putString("key", Base64.encodeToString(key, Base64.NO_WRAP))
                .putInt("scheme", SCHEME)
                .putString("device", hex(id))
                .putString("code", code.toString())
                .putString("mac", mac)
                .putBoolean("paired", false)
                .apply();
        failures = 0;
        publish(w, new Snapshot(PAIRING, mac, code.toString(), null, Collections.emptyList()));
    }

    // ---- Finding the Mac -------------------------------------------------------------------

    private void search(Handler w) {
        if (searchingSince == 0) searchingSince = SystemClock.elapsedRealtime();
        if (sp.getString("host", null) == null) {
            boolean waited = SystemClock.elapsedRealtime() - searchingSince > SEARCH_MS;
            publish(w, new Snapshot(waited ? OFFLINE : SEARCHING, sp.getString("mac", "Mac"), null, null,
                    Collections.emptyList()));
        }
        if (discovery != null) return;
        NsdManager nsd = (NsdManager) app.getSystemService(Context.NSD_SERVICE);
        if (nsd == null) return;
        discovery = new NsdManager.DiscoveryListener() {
            @Override
            public void onServiceFound(NsdServiceInfo info) {
                onWorker(() -> {
                    if (resolving || discovery != this) return;
                    resolving = true;
                    nsd.resolveService(info, resolver(nsd));
                });
            }

            @Override
            public void onStartDiscoveryFailed(String type, int error) {
                onWorker(() -> {
                    if (discovery == this) discovery = null;
                });
            }

            @Override
            public void onDiscoveryStarted(String type) {}

            @Override
            public void onDiscoveryStopped(String type) {}

            @Override
            public void onServiceLost(NsdServiceInfo info) {}

            @Override
            public void onStopDiscoveryFailed(String type, int error) {}
        };
        try {
            nsd.discoverServices(SERVICE, NsdManager.PROTOCOL_DNS_SD, discovery);
        } catch (RuntimeException e) {
            discovery = null;
        }
    }

    private NsdManager.ResolveListener resolver(NsdManager nsd) {
        return new NsdManager.ResolveListener() {
            @Override
            public void onServiceResolved(NsdServiceInfo info) {
                onWorker(() -> {
                    resolving = false;
                    Map<String, byte[]> txt = info.getAttributes();
                    String id = txt.get("id") != null ? new String(txt.get("id"), StandardCharsets.UTF_8) : "";
                    String known = sp.getString("helper", null);
                    // Once paired, stick to that Mac.
                    if (known != null && sp.getString("key", null) != null && !known.equals(id)) return;
                    InetAddress a = info.getHost();
                    String host = a instanceof Inet6Address
                            ? "[" + a.getHostAddress().replace("%", "%25") + "]" : a.getHostAddress();
                    sp.edit().putString("host", host + ":" + info.getPort()).putString("helper", id).apply();
                    failures = 0;
                    searchingSince = 0;
                    stopDiscovery();
                    Handler w = worker;
                    if (w != null) {
                        w.removeCallbacksAndMessages(null);
                        w.post(() -> poll(w));
                    }
                });
            }

            @Override
            public void onResolveFailed(NsdServiceInfo info, int error) {
                onWorker(() -> resolving = false);
            }
        };
    }

    private void stopDiscovery() {
        searchingSince = 0;
        if (discovery == null) return;
        NsdManager nsd = (NsdManager) app.getSystemService(Context.NSD_SERVICE);
        try {
            nsd.stopServiceDiscovery(discovery);
        } catch (RuntimeException ignored) {
            // Already stopped.
        }
        discovery = null;
        resolving = false;
    }

    private void onWorker(Runnable r) {
        Handler w = worker;
        if (w != null) w.post(r);
    }

    /** Shown only if w (the worker that got it) is still the current one when it reaches the main thread. */
    private void publish(Handler w, Snapshot s) {
        main.post(() -> {
            if (w != worker || w == null) return;
            last = s;
            for (Listener l : new ArrayList<>(listeners)) l.onAgents(s);
        });
    }

    // ---- Helpers ---------------------------------------------------------------------------

    private static HttpURLConnection open(String host, String path) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL("http://" + host + path).openConnection();
        c.setConnectTimeout(2500);
        c.setReadTimeout(4000);
        c.setUseCaches(false);
        c.setInstanceFollowRedirects(false);
        return c;
    }

    private static byte[] readAll(InputStream in) throws IOException {
        if (in == null) return new byte[0];
        try (InputStream s = in) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            for (int n; (n = s.read(buf)) > 0; ) {
                out.write(buf, 0, n);
                if (out.size() > 1 << 20) throw new IOException("reply too large");
            }
            return out.toByteArray();
        }
    }

    private static byte[] hmac(byte[] key, byte[] data) throws GeneralSecurityException {
        Mac m = Mac.getInstance("HmacSHA256");
        m.init(new SecretKeySpec(key, "HmacSHA256"));
        return m.doFinal(data);
    }

    private static byte[] sha256(byte[]... parts) throws GeneralSecurityException {
        MessageDigest d = MessageDigest.getInstance("SHA-256");
        for (byte[] p : parts) d.update(p);
        return d.digest();
    }

    /** SHA-256 over length-prefixed parts (derive in LumenAgents.swift does the same). */
    private static byte[] derive(byte[]... parts) throws GeneralSecurityException {
        MessageDigest d = MessageDigest.getInstance("SHA-256");
        for (byte[] p : parts) {
            d.update(new byte[]{(byte) (p.length >> 8), (byte) p.length});
            d.update(p);
        }
        return d.digest();
    }

    private static String hex(byte[] bytes) {
        StringBuilder b = new StringBuilder(bytes.length * 2);
        for (byte x : bytes) b.append(Character.forDigit((x >> 4) & 0xF, 16)).append(Character.forDigit(x & 0xF, 16));
        return b.toString();
    }
}
