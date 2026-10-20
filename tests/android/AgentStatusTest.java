package local.tvhome;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Predicate;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Offline tests for AgentStatus's worker on the JVM; run with tests/android/run.sh. Android's classes are small
 * stand-ins (stubs/), and the Mac is a fake helper in this process on 127.0.0.1 that seals replies like the real
 * one. Nothing touches a TV, an emulator, ADB or the real helper.
 */
public final class AgentStatusTest {
    interface Script {
        void handle(HttpExchange x, String target, String time) throws Exception;
    }

    static final byte[] KEY = new byte[32];
    static volatile Script mac;
    static final List<AgentStatus.Snapshot> seen = new ArrayList<>();
    static int failed;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok    " : "  FAIL  ") + what);
        if (!ok) failed++;
    }

    // ---- The fake Mac ---------------------------------------------------------------------

    static String chat(String title) {
        return "{\"id\":\"" + title + "\",\"title\":\"" + title + "\",\"state\":\"done\",\"detail\":\"Finished\"}";
    }

    static String status(long version, String macName, String... titles) {
        List<String> chats = new ArrayList<>();
        for (String t : titles) chats.add(chat(t));
        return "{\"v\":1,\"version\":" + version + ",\"mac\":\"" + macName + "\",\"t3\":\"ok\",\"chats\":["
                + String.join(",", chats) + "]}";
    }

    static void sealed(HttpExchange x, String time, String body) throws Exception {
        byte[] nonce = new byte[12];
        new SecureRandom().nextBytes(nonce);
        Cipher aes = Cipher.getInstance("AES/GCM/NoPadding");
        aes.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(KEY, "AES"), new GCMParameterSpec(128, nonce));
        aes.updateAAD(time.getBytes(StandardCharsets.UTF_8));
        byte[] box = aes.doFinal(body.getBytes(StandardCharsets.UTF_8));
        byte[] out = new byte[12 + box.length];
        System.arraycopy(nonce, 0, out, 0, 12);
        System.arraycopy(box, 0, out, 12, box.length);
        send(x, 200, out);
    }

    static void send(HttpExchange x, int code, byte[] body) throws Exception {
        x.sendResponseHeaders(code, body.length);
        try (OutputStream o = x.getResponseBody()) {
            o.write(body);
        }
    }

    static void await(CountDownLatch l) {
        try {
            l.await(120, TimeUnit.SECONDS);
        } catch (InterruptedException ignored) {
        }
    }

    // ---- The TV side ----------------------------------------------------------------------

    static final Handler main = new Handler(Looper.getMainLooper());

    static void onMain(Runnable r) throws InterruptedException {
        CountDownLatch done = new CountDownLatch(1);
        main.post(() -> {
            r.run();
            done.countDown();
        });
        done.await();
    }

    static List<String> titles(AgentStatus.Snapshot s) {
        List<String> out = new ArrayList<>();
        for (AgentStatus.Chat c : s.chats) out.add(c.title);
        return out;
    }

    static synchronized boolean any(Predicate<AgentStatus.Snapshot> p) {
        for (AgentStatus.Snapshot s : seen) if (p.test(s)) return true;
        return false;
    }

    static boolean until(double seconds, Predicate<AgentStatus.Snapshot> p) throws InterruptedException {
        long end = System.nanoTime() + (long) (seconds * 1e9);
        while (System.nanoTime() < end) {
            if (any(p)) return true;
            Thread.sleep(50);
        }
        return any(p);
    }

    static boolean showing(AgentStatus.Snapshot s, String title) {
        return s.phase == AgentStatus.READY && titles(s).contains(title);
    }

    static void paired(SharedPreferences sp, int port) {
        sp.edit().putString("host", "127.0.0.1:" + port).putString("key", Base64.getEncoder().encodeToString(KEY))
                .putInt("scheme", 2).putString("device", "0011223344556677").putString("mac", "Test Mac")
                .putBoolean("paired", true).apply();
    }

    /** Pauses the TV's thread when it saves a reply naming this Mac, between reading the reply and showing it. */
    static void pauseAt(String macName, CountDownLatch paused, CountDownLatch resume) {
        SharedPreferences.beforeApply = put -> {
            if (!macName.equals(put.get("mac"))) return;
            paused.countDown();
            await(resume);
        };
    }

    public static void main(String[] args) throws Exception {
        new SecureRandom().nextBytes(KEY);
        HttpServer server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        server.setExecutor(Executors.newCachedThreadPool(r -> {
            Thread t = new Thread(r);
            t.setDaemon(true);
            return t;
        }));
        server.createContext("/", x -> {
            try {
                String time = x.getRequestHeaders().getFirst("X-Lumen-Time");
                mac.handle(x, x.getRequestURI().toString(), time == null ? "" : time);
            } catch (Exception ignored) {
                // The TV let go of the request.
            } finally {
                x.close();
            }
        });
        server.start();
        int port = server.getAddress().getPort();

        Context ctx = new Context();
        SharedPreferences sp = ctx.prefs;
        paired(sp, port);
        AgentStatus agents = AgentStatus.get(ctx);
        AgentStatus.Listener l = s -> {
            synchronized (AgentStatusTest.class) {
                seen.add(s);
            }
        };
        onMain(() -> agents.addListener(l));

        System.out.println("Starting");
        CountDownLatch gate1 = new CountDownLatch(1);
        mac = (x, target, time) -> {
            if (!target.contains("wait=")) {
                sealed(x, time, status(1, "Test Mac", "Fresh"));
            } else {
                await(gate1);
                sealed(x, time, status(2, "Stale Mac", "STALE"));
            }
        };
        onMain(() -> agents.want(AgentStatus.HOME, true));
        check(until(5, s -> showing(s, "Fresh")), "the TV shows the Mac's chats");

        System.out.println("A reply that arrives after the TV stopped and started again");
        CountDownLatch paused = new CountDownLatch(1), resume = new CountDownLatch(1);
        pauseAt("Stale Mac", paused, resume);
        CountDownLatch gate2 = new CountDownLatch(1);
        // Its waiting request gets an answer, and the TV is between reading it and showing it...
        gate1.countDown();
        check(paused.await(10, TimeUnit.SECONDS), "(the old request has its reply)");
        Script next = (x, target, time) -> {
            if (!target.contains("wait=")) {
                sealed(x, time, status(5, "Test Mac", "Fresh 2"));
            } else {
                await(gate2);
                sealed(x, time, status(6, "Stale Mac 2", "STALE 2"));
            }
        };
        mac = next;
        // ...when it stops listening and starts again.
        onMain(() -> {
            agents.want(AgentStatus.HOME, false);
            synchronized (AgentStatusTest.class) {
                seen.clear();
            }
            agents.want(AgentStatus.HOME, true);
        });
        resume.countDown();
        check(until(5, s -> showing(s, "Fresh 2")), "the new start shows current chats");
        Thread.sleep(500);
        check(!any(s -> showing(s, "STALE")), "the old reply is never shown");

        System.out.println("A reply that arrives after Pair again");
        CountDownLatch paused2 = new CountDownLatch(1), resume2 = new CountDownLatch(1);
        pauseAt("Stale Mac 2", paused2, resume2);
        AtomicInteger forgets = new AtomicInteger();
        gate2.countDown();
        check(paused2.await(10, TimeUnit.SECONDS), "(the old request has its reply)");
        mac = (x, target, time) -> {
            if (target.startsWith("/forget")) forgets.incrementAndGet();
            send(x, target.startsWith("/forget") ? 200 : 503, new byte[0]);
        };
        onMain(() -> {
            synchronized (AgentStatusTest.class) {
                seen.clear();
            }
            agents.pairAgain();
        });
        resume2.countDown();
        Thread.sleep(1500);
        check(!any(s -> s.phase == AgentStatus.READY), "nothing from the old key is shown after Pair again");
        check(sp.getString("key", null) == null && !sp.getBoolean("paired", true), "the key is forgotten");
        check(forgets.get() == 1, "and the Mac is asked to forget it");

        System.out.println("The Mac fails a waiting request");
        onMain(() -> agents.want(AgentStatus.HOME, false));
        SharedPreferences.beforeApply = null;
        paired(sp, port);
        AtomicInteger errors = new AtomicInteger();
        mac = (x, target, time) -> {
            if (!target.contains("wait=")) {
                sealed(x, time, status(7, "Test Mac", "Fresh 3"));
            } else {
                errors.incrementAndGet();
                send(x, 500, new byte[0]);
            }
        };
        onMain(() -> {
            synchronized (AgentStatusTest.class) {
                seen.clear();
            }
            agents.want(AgentStatus.HOME, true);
        });
        check(until(5, s -> showing(s, "Fresh 3")), "(chats are showing)");
        check(until(3, s -> s.phase == AgentStatus.OFFLINE && s.chats.isEmpty()) && errors.get() == 1,
                "the first failure clears them at once");

        System.out.println("The Mac turns the TV away (unsealed, so anyone could send it)");
        onMain(() -> agents.want(AgentStatus.HOME, false));
        mac = (x, target, time) -> {
            if (!target.contains("wait=")) sealed(x, time, status(8, "Test Mac", "Fresh 4"));
            else send(x, 401, "{\"error\":\"unknown device\"}".getBytes(StandardCharsets.UTF_8));
        };
        onMain(() -> {
            synchronized (AgentStatusTest.class) {
                seen.clear();
            }
            agents.want(AgentStatus.HOME, true);
        });
        check(until(5, s -> showing(s, "Fresh 4")), "(chats are showing)");
        check(until(3, s -> s.phase == AgentStatus.OFFLINE && s.chats.isEmpty()), "the chats are cleared at once");
        check(sp.getString("key", null) != null && sp.getBoolean("paired", false), "but the key is kept");

        System.out.println("A Mac that accepts the connection and never answers");
        onMain(() -> agents.want(AgentStatus.HOME, false));
        CountDownLatch never = new CountDownLatch(1);
        mac = (x, target, time) -> await(never);
        long started = System.nanoTime();
        onMain(() -> {
            synchronized (AgentStatusTest.class) {
                seen.clear();
            }
            agents.want(AgentStatus.HOME, true);
        });
        boolean offline = until(10, s -> s.phase == AgentStatus.OFFLINE);
        double took = (System.nanoTime() - started) / 1e9;
        check(offline && took < 8, String.format("an asking-at-once request gives up after its 4 s (%.1f s)", took));
        check(!any(s -> s.phase == AgentStatus.READY), "and shows no chats meanwhile");

        never.countDown();
        onMain(() -> agents.want(AgentStatus.HOME, false));
        server.stop(0);
        System.out.println(failed == 0 ? "All passed." : failed + " failed.");
        System.exit(failed == 0 ? 0 : 1);
    }
}
