package local.tvhome;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/**
 * Google TV always sends Home to its own launcher, so this service catches the Home button
 * and opens Lumen. If the stock home screen still appears some other way, it hops back to Lumen.
 */
public class HomeKeyService extends AccessibilityService {
    private static final String STOCK_HOME = "com.google.android.apps.tv.launcherx";

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        if (event.getKeyCode() != KeyEvent.KEYCODE_HOME) return false;
        if (event.getAction() == KeyEvent.ACTION_UP && !event.isCanceled()) goHome();
        return true;
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return;
        CharSequence pkg = event.getPackageName(), cls = event.getClassName();
        if (pkg != null && cls != null && STOCK_HOME.contentEquals(pkg)
                && cls.toString().endsWith(".home.HomeActivity")) {
            goHome();
        }
    }

    @Override
    public void onInterrupt() {}

    private void goHome() {
        startActivity(new Intent(this, HomeActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED));
    }
}
