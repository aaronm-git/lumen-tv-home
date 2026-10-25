package local.tvhome;

import android.service.notification.NotificationListenerService;

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
