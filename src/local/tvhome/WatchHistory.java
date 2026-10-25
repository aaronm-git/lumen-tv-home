package local.tvhome;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.BitmapDrawable;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class WatchHistory {
    interface Listener {
        void onHistoryChanged();
    }

    static final class Show {
        final String id;
        final String pkg;
        String title, subtitle;
        long position, duration, time;
        private Bitmap art;
        private boolean artLoaded;
        private int accent;

        private Show(String id, String pkg) {
            this.id = id;
            this.pkg = pkg;
        }

        float progress() {
            return duration > 0 && position >= 0 ? Math.min(1f, (float) position / duration) : -1;
        }

        boolean finished() {
            if (duration <= 0 || position < 0) return false;
            long left = duration - position;
            return left <= duration / 10 || (duration >= 20 * 60_000 && left <= 3 * 60_000);
        }
    }

    private static final int MAX = 20;
    private static final int ART_PX = 384;
    private static WatchHistory instance;

    private final File file;
    private final File artDir;
    private final List<Show> shows = new ArrayList<>();
    private final List<Listener> listeners = new ArrayList<>();
    private final ExecutorService io = Executors.newSingleThreadExecutor();

    static WatchHistory get(Context c) {
        if (instance == null) instance = new WatchHistory(c.getApplicationContext());
        return instance;
    }

    private WatchHistory(Context c) {
        file = new File(c.getFilesDir(), "watch-history.json");
        artDir = new File(c.getFilesDir(), "art");
        try {
            JSONArray arr = new JSONArray(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
            for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.getJSONObject(i);
                Show s = new Show(o.getString("id"), o.getString("pkg"));
                s.title = o.getString("title");
                s.subtitle = o.optString("subtitle", null);
                s.position = o.optLong("position", -1);
                s.duration = o.optLong("duration", 0);
                s.time = o.optLong("time", 0);
                shows.add(s);
            }
        } catch (IOException | JSONException e) {

        }
    }

    List<Show> list() {
        return new ArrayList<>(shows);
    }

    void addListener(Listener l) {
        listeners.add(l);
    }

    void removeListener(Listener l) {
        listeners.remove(l);
    }

    Show record(String pkg, String title, String subtitle, Bitmap art, long position, long duration) {
        Show s = null;
        for (Show x : shows) {
            if (x.pkg.equals(pkg) && (x.title.equals(title) || (subtitle != null && subtitle.equals(x.subtitle)))) {
                s = x;
                break;
            }
        }
        if (s == null) s = new Show(UUID.randomUUID().toString(), pkg);
        shows.remove(s);
        shows.add(0, s);
        s.title = title;
        s.subtitle = subtitle;
        s.position = position;
        s.duration = duration;
        s.time = System.currentTimeMillis();
        if (art != null) setArt(s, art);
        while (shows.size() > MAX) forget(shows.remove(shows.size() - 1));
        changed();
        return s;
    }

    void progress(Show s, long position, long duration) {
        if (!shows.contains(s)) return;
        s.position = position;
        if (duration > 0) s.duration = duration;
        changed();
    }

    void remove(Show s) {
        if (shows.remove(s)) {
            forget(s);
            changed();
        }
    }

    void clear() {
        for (Show s : shows) forget(s);
        shows.clear();
        changed();
    }

    Bitmap art(Show s) {
        if (!s.artLoaded) {
            s.artLoaded = true;
            File f = artFile(s);
            if (f.exists()) {
                BitmapFactory.Options o = new BitmapFactory.Options();
                o.inPreferredConfig = Bitmap.Config.RGB_565;
                s.art = BitmapFactory.decodeFile(f.getPath(), o);
            }
            s.accent = s.art != null ? Ui.accent(new BitmapDrawable(null, s.art)) : 0;
        }
        return s.art;
    }

    int accent(Show s) {
        art(s);
        return s.accent;
    }

    private void setArt(Show s, Bitmap source) {
        float scale = Math.min(1f, (float) ART_PX / Math.max(source.getWidth(), source.getHeight()));
        Bitmap small = scale < 1f ? Bitmap.createScaledBitmap(source,
                Math.round(source.getWidth() * scale), Math.round(source.getHeight() * scale), true) : source;
        s.art = small;
        s.artLoaded = true;
        s.accent = Ui.accent(new BitmapDrawable(null, small));
        File f = artFile(s);
        io.execute(() -> {
            artDir.mkdirs();
            try (FileOutputStream out = new FileOutputStream(f)) {
                small.compress(Bitmap.CompressFormat.JPEG, 85, out);
            } catch (IOException ignored) {

            }
        });
    }

    private void forget(Show s) {
        File f = artFile(s);
        io.execute(f::delete);
    }

    private File artFile(Show s) {
        return new File(artDir, s.id + ".jpg");
    }

    private void changed() {
        JSONArray arr = new JSONArray();
        try {
            for (Show s : shows) {
                arr.put(new JSONObject()
                        .put("id", s.id).put("pkg", s.pkg).put("title", s.title).put("subtitle", s.subtitle)
                        .put("position", s.position).put("duration", s.duration).put("time", s.time));
            }
        } catch (JSONException e) {
            return;
        }
        byte[] data = arr.toString().getBytes(StandardCharsets.UTF_8);
        io.execute(() -> {
            File tmp = new File(file.getPath() + ".tmp");
            try {
                Files.write(tmp.toPath(), data);
                if (!tmp.renameTo(file)) tmp.delete();
            } catch (IOException ignored) {

            }
        });
        for (Listener l : new ArrayList<>(listeners)) l.onHistoryChanged();
    }
}
