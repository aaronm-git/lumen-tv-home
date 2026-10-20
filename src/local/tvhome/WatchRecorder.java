package local.tvhome;

import android.content.Context;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * Adds what you watch to the watch history. Something counts once it has played for 20 seconds
 * (so trailers and quick peeks don't), and its progress is saved every 30 seconds and on pause.
 */
final class WatchRecorder implements NowPlaying.Listener {
    private static final long DWELL_MS = 20_000;
    private static final long TICK_MS = 30_000;
    /** Music, casting and live TV: not shows you can go back to. */
    private static final Set<String> SKIP = new HashSet<>(Arrays.asList(
            "com.spotify.tv.android",
            "com.google.android.youtube.tvmusic",
            "com.sony.dtv.osat.music",
            "com.google.android.apps.mediashell",
            "com.sony.dtv.airplayapp",
            "com.sonyericsson.dlna",
            "com.sony.huey.dlna.module",
            "com.sony.dtv.tvx",
            "com.android.tv"));

    private final Context context;
    private final WatchHistory history;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable tick = this::tick;

    private String activeKey;
    private MediaController active;
    private MediaMetadata activeMetadata;
    private WatchHistory.Show recorded;
    private long lastPosition = -1;

    WatchRecorder(Context c) {
        context = c;
        history = WatchHistory.get(c);
    }

    @Override
    public void onNowPlaying(MediaController c, MediaMetadata md, boolean playing) {
        String key = playing && NowPlaying.title(md) != null && !SKIP.contains(c.getPackageName())
                ? c.getPackageName() + "\n" + NowPlaying.title(md) + "\n" + NowPlaying.subtitle(md) : null;
        if (key != null && key.equals(activeKey)) return;  // Same thing, still playing.

        // Paused, stopped or switched to something else: keep where it got to.
        saveProgress();
        handler.removeCallbacks(tick);
        activeKey = key;
        active = key != null ? c : null;
        activeMetadata = md;
        recorded = null;
        lastPosition = -1;
        if (key != null) handler.postDelayed(tick, DWELL_MS);
    }

    void stop() {
        saveProgress();
        handler.removeCallbacks(tick);
        active = null;
        activeKey = null;
        recorded = null;
    }

    private void tick() {
        if (active == null) return;
        if (!Prefs.continueWatching(context)) {
            handler.postDelayed(tick, TICK_MS);
            return;
        }
        if (recorded == null) {
            recorded = history.record(active.getPackageName(), NowPlaying.title(activeMetadata),
                    NowPlaying.subtitle(activeMetadata), NowPlaying.art(activeMetadata, 384), position(), duration());
        } else {
            history.progress(recorded, position(), duration());
        }
        handler.postDelayed(tick, TICK_MS);
    }

    /** Nothing is written while Continue watching is off. */
    private void saveProgress() {
        if (recorded != null && Prefs.continueWatching(context)) history.progress(recorded, position(), duration());
    }

    /** Where playback is now, allowing for time passed since the app last reported it. */
    private long position() {
        PlaybackState s = active != null ? active.getPlaybackState() : null;
        if (s != null && s.getPosition() >= 0) {
            long pos = s.getPosition();
            if (s.getState() == PlaybackState.STATE_PLAYING && s.getLastPositionUpdateTime() > 0) {
                pos += (long) ((SystemClock.elapsedRealtime() - s.getLastPositionUpdateTime()) * s.getPlaybackSpeed());
            }
            lastPosition = pos;
        }
        return lastPosition;
    }

    private long duration() {
        return activeMetadata != null ? activeMetadata.getLong(MediaMetadata.METADATA_KEY_DURATION) : 0;
    }
}
