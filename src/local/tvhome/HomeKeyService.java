package local.tvhome;

import android.accessibilityservice.AccessibilityService;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.os.PowerManager;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

import java.util.HashMap;
import java.util.Map;

/**
 * Google TV always sends Home to its own launcher, so this service catches the Home button
 * and opens Lumen. If the stock home screen still appears some other way, it hops back to Lumen.
 *
 * It's always running, so it also shows agent notifications: when a T3 Code chat finishes, fails or needs you
 * while you're in another app, a small card appears over it (see AgentAlert). Only while the TV is on.
 */
public class HomeKeyService extends AccessibilityService {
    /**
     * Google TV's home screen (and its .home.HomeActivity below; also in res/xml/home_key_service.xml). Other
     * Android TV devices are untested; there the normal default-home choice may work without this service.
     */
    private static final String STOCK_HOME = "com.google.android.apps.tv.launcherx";

    private AgentStatus agents;
    private AgentAlert alert;
    /** Each chat's state when we last heard; null until the first reply, so old news isn't announced. */
    private Map<String, String> lastStates;
    private final AgentStatus.Listener agentListener = this::onAgents;
    private final SharedPreferences.OnSharedPreferenceChangeListener prefsListener = (sp, key) -> update();
    private final BroadcastReceiver screenReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context c, Intent i) {
            update();
        }
    };

    @Override
    protected void onServiceConnected() {
        agents = AgentStatus.get(this);
        alert = new AgentAlert(this);
        IntentFilter screen = new IntentFilter(Intent.ACTION_SCREEN_ON);
        screen.addAction(Intent.ACTION_SCREEN_OFF);
        registerReceiver(screenReceiver, screen);
        Prefs.shared(this).registerOnSharedPreferenceChangeListener(prefsListener);
        agents.addListener(agentListener);
        update();
    }

    @Override
    public void onDestroy() {
        if (agents != null) {
            unregisterReceiver(screenReceiver);
            Prefs.shared(this).unregisterOnSharedPreferenceChangeListener(prefsListener);
            agents.removeListener(agentListener);
            agents.want(AgentStatus.NOTIFY, false);
            alert.hide();
        }
        super.onDestroy();
    }

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

    /** Listens to the Mac only while notifications are on and the screen is awake. */
    private void update() {
        boolean on = Prefs.agentAlerts(this);
        if (!on) lastStates = null;
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        agents.want(AgentStatus.NOTIFY, on && pm.isInteractive());
    }

    private void onAgents(AgentStatus.Snapshot s) {
        if (!s.active() || !Prefs.agentAlerts(this)) return;
        Map<String, String> now = new HashMap<>();
        AgentStatus.Chat first = null;
        int count = 0;
        for (AgentStatus.Chat c : s.chats) {
            now.put(c.id, c.state);
            if (lastStates != null && !"working".equals(c.state) && !c.state.equals(lastStates.get(c.id))) {
                if (first == null) first = c;  // Chats come most urgent first.
                count++;
            }
        }
        lastStates = now;
        // On the home screen the Agents card already shows it.
        if (first != null && !HomeActivity.showing) alert.show(first, count, s.mac);
    }
}
