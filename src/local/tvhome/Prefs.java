package local.tvhome;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/** Favourites (in order) and hidden apps, kept on the TV between restarts. */
final class Prefs {
    final List<String> favorites;
    final Set<String> hidden;
    /** "rows" (favourites row + apps row) or "grid" (every app in one grid). */
    String layout;
    boolean showContinue;
    boolean showNowPlaying;
    /** T3 Code chats from the Lumen Agents helper on the Mac. */
    boolean showAgents;
    /** A card over other apps when a chat finishes, fails or needs you. */
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

    /** For the background recorder, which has no Prefs of its own. */
    static boolean continueWatching(Context c) {
        return shared(c).getBoolean("showContinue", true);
    }

    /** For the Home button service, which shows agent notifications. */
    static boolean agentAlerts(Context c) {
        return shared(c).getBoolean("agentAlerts", agentsDefault(c));
    }

    /**
     * Agents talk to the network and show chat text on the TV, so they start off. A TV that already has a
     * key from the Mac (paired before this default existed) keeps them on.
     */
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
