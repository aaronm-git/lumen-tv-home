package local.tvhome;

import android.content.ComponentName;
import android.content.Context;
import android.graphics.Bitmap;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;

import java.util.ArrayList;
import java.util.List;

final class NowPlaying {
    interface Listener {

        void onNowPlaying(MediaController controller, MediaMetadata metadata, boolean playing);
    }

    private final MediaSessionManager msm;
    private final ComponentName access;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Listener listener;
    private final List<Watched> watched = new ArrayList<>();
    private final MediaSessionManager.OnActiveSessionsChangedListener sessionsChanged = this::watch;
    private boolean running;

    NowPlaying(Context c, Listener listener) {
        msm = c.getSystemService(MediaSessionManager.class);
        access = new ComponentName(c, MediaAccess.class);
        this.listener = listener;
    }

    boolean allowed() {
        try {
            msm.getActiveSessions(access);
            return true;
        } catch (SecurityException e) {
            return false;
        }
    }

    void start() {
        if (running) return;
        try {
            msm.addOnActiveSessionsChangedListener(sessionsChanged, access, handler);
        } catch (SecurityException e) {
            listener.onNowPlaying(null, null, false);
            return;
        }
        running = true;
        watch(msm.getActiveSessions(access));
    }

    void stop() {
        if (!running) return;
        running = false;
        msm.removeOnActiveSessionsChangedListener(sessionsChanged);
        for (Watched w : watched) w.controller.unregisterCallback(w);
        watched.clear();
    }

    private void watch(List<MediaController> sessions) {
        for (Watched w : watched) w.controller.unregisterCallback(w);
        watched.clear();
        if (sessions != null) for (MediaController c : sessions) watched.add(new Watched(c));
        pick();
    }

    private void pick() {
        Watched best = null;
        for (Watched w : watched) {
            if (title(w.metadata) == null) continue;
            if (isPlaying(w.state)) {
                best = w;
                break;
            }
            if (best == null && w.state == PlaybackState.STATE_PAUSED) best = w;
        }
        if (best == null) listener.onNowPlaying(null, null, false);
        else listener.onNowPlaying(best.controller, best.metadata, isPlaying(best.state));
    }

    private final class Watched extends MediaController.Callback {
        final MediaController controller;
        MediaMetadata metadata;
        int state;

        Watched(MediaController c) {
            controller = c;
            metadata = c.getMetadata();
            state = stateOf(c.getPlaybackState());
            c.registerCallback(this, handler);
        }

        @Override
        public void onPlaybackStateChanged(PlaybackState s) {
            int next = stateOf(s);
            if (next == state) return;
            state = next;
            pick();
        }

        @Override
        public void onMetadataChanged(MediaMetadata m) {
            metadata = m;
            pick();
        }

        @Override
        public void onSessionDestroyed() {
            state = PlaybackState.STATE_NONE;
            pick();
        }
    }

    private static int stateOf(PlaybackState s) {
        return s == null ? PlaybackState.STATE_NONE : s.getState();
    }

    private static boolean isPlaying(int state) {
        return state == PlaybackState.STATE_PLAYING || state == PlaybackState.STATE_BUFFERING;
    }

    static String title(MediaMetadata md) {
        return first(md, MediaMetadata.METADATA_KEY_DISPLAY_TITLE, MediaMetadata.METADATA_KEY_TITLE);
    }

    static String subtitle(MediaMetadata md) {
        return first(md, MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, MediaMetadata.METADATA_KEY_ARTIST,
                MediaMetadata.METADATA_KEY_ALBUM);
    }

    static MediaController find(Context c, String pkg, String title) {
        try {
            MediaSessionManager msm = c.getSystemService(MediaSessionManager.class);
            for (MediaController mc : msm.getActiveSessions(new ComponentName(c, MediaAccess.class))) {
                if (mc.getPackageName().equals(pkg) && title.equals(title(mc.getMetadata()))) return mc;
            }
        } catch (SecurityException e) {

        }
        return null;
    }

    static Bitmap art(MediaMetadata md, int maxPx) {
        if (md == null) return null;
        for (String key : new String[]{MediaMetadata.METADATA_KEY_DISPLAY_ICON,
                MediaMetadata.METADATA_KEY_ART, MediaMetadata.METADATA_KEY_ALBUM_ART}) {
            Bitmap b = md.getBitmap(key);
            if (b == null) continue;
            float scale = Math.min(1f, (float) maxPx / Math.max(b.getWidth(), b.getHeight()));
            return scale < 1f ? Bitmap.createScaledBitmap(b,
                    Math.round(b.getWidth() * scale), Math.round(b.getHeight() * scale), true) : b;
        }
        return null;
    }

    private static String first(MediaMetadata md, String... keys) {
        if (md == null) return null;
        for (String key : keys) {
            CharSequence t = md.getText(key);
            if (!TextUtils.isEmpty(t)) return t.toString();
        }
        return null;
    }
}
