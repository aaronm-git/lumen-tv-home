package local.tvhome;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

final class Prefs {
    final List<String> favorites;
    final Set<String> hidden;

    String layout;
    boolean showContinue;
    boolean showNowPlaying;

    boolean showAgents;

    boolean agentAlerts;
    private final SharedPreferences sp;

    Prefs(Context c, String[] defaultFavorites) {
        sp = c.getSharedPreferences("home", Context.MODE_PRIVATE);
        String favs = sp.getString("favorites", null);
        favorites = favs == null ? new ArrayList<>(Arrays.asList(defaultFavorites)) : split(favs);
        hidden = new LinkedHashSet<>(split(sp.getString("hidden", "")));
        layout = sp.getString("layout", "rows");
        showContinue = sp.getBoolean("showContinue", true);
        showNowPlaying = sp.getBoolean("showNowPlaying", true);
        showAgents = sp.getBoolean("showAgents", agentsDefault(c));
        agentAlerts = sp.getBoolean("agentAlerts", agentsDefault(c));
    }

    void save() {
        sp.edit()
                .putString("favorites", String.join(",", favorites))
                .putString("hidden", String.join(",", hidden))
                .putString("layout", layout)
                .putBoolean("showContinue", showContinue)
                .putBoolean("showNowPlaying", showNowPlaying)
                .putBoolean("showAgents", showAgents)
                .putBoolean("agentAlerts", agentAlerts)
                .apply();
    }

    static SharedPreferences shared(Context c) {
        return c.getSharedPreferences("home", Context.MODE_PRIVATE);
    }

    static boolean continueWatching(Context c) {
        return shared(c).getBoolean("showContinue", true);
    }

    static boolean agentAlerts(Context c) {
        return shared(c).getBoolean("agentAlerts", agentsDefault(c));
    }

    private static boolean agentsDefault(Context c) {
        SharedPreferences agents = c.getSharedPreferences("agents", Context.MODE_PRIVATE);
        return agents.getBoolean("paired", false) || agents.contains("key");
    }

    private static List<String> split(String s) {
        List<String> out = new ArrayList<>();
        for (String part : s.split(",")) if (!part.isEmpty()) out.add(part);
        return out;
    }
}
