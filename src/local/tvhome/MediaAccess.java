package local.tvhome;

import android.service.notification.NotificationListenerService;

/**
 * Android only shares "what's playing" with apps that hold notification-listener access, so Lumen
 * declares this listener. It never reads notifications; it only follows media sessions so the
 * shows you play can appear in Continue watching.
 */
public class MediaAccess extends NotificationListenerService {
    private NowPlaying sessions;
    private WatchRecorder recorder;

    @Override
    public void onListenerConnected() {
        recorder = new WatchRecorder(this);
        sessions = new NowPlaying(this, recorder);
        sessions.start();
    }

    @Override
    public void onListenerDisconnected() {
        if (sessions != null) sessions.stop();
        if (recorder != null) recorder.stop();
        sessions = null;
        recorder = null;
    }
}
