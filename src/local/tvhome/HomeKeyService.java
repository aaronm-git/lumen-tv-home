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

public class HomeKeyService extends AccessibilityService {

    private static final String STOCK_HOME = "com.google.android.apps.tv.launcherx";

    private AgentStatus agents;
    private AgentAlert alert;

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

    private void update() {
        boolean on = Prefs.agentAlerts(this);
        if (!on) {
            lastStates = null;
            alert.hide();
        }
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        agents.want(AgentStatus.NOTIFY, on && pm.isInteractive());
    }

    private void onAgents(AgentStatus.Snapshot s) {
        if (!Prefs.agentAlerts(this)) return;
        if (!s.active()) {

            alert.hide();
            lastStates = null;
            return;
        }
        Map<String, String> now = new HashMap<>();
        AgentStatus.Chat first = null;
        int count = 0;
        for (AgentStatus.Chat c : s.chats) {
            now.put(c.id, c.state);
            if (lastStates != null && !"working".equals(c.state) && !c.state.equals(lastStates.get(c.id))) {
                if (first == null) first = c;
                count++;
            }
        }
        lastStates = now;

        if (first != null && !HomeActivity.showing) alert.show(first, count, s.mac);
    }
}
