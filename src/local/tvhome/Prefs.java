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
    private final SharedPreferences sp;

    Prefs(Context c, String[] defaultFavorites) {
        sp = c.getSharedPreferences("home", Context.MODE_PRIVATE);
        String favs = sp.getString("favorites", null);
        favorites = favs == null ? new ArrayList<>(Arrays.asList(defaultFavorites)) : split(favs);
        hidden = new LinkedHashSet<>(split(sp.getString("hidden", "")));
        layout = sp.getString("layout", "rows");
        showContinue = sp.getBoolean("showContinue", true);
        showNowPlaying = sp.getBoolean("showNowPlaying", true);
    }

    void save() {
        sp.edit()
                .putString("favorites", String.join(",", favorites))
                .putString("hidden", String.join(",", hidden))
                .putString("layout", layout)
                .putBoolean("showContinue", showContinue)
                .putBoolean("showNowPlaying", showNowPlaying)
                .apply();
    }

    /** For the background recorder, which has no Prefs of its own. */
    static boolean continueWatching(Context c) {
        return c.getSharedPreferences("home", Context.MODE_PRIVATE).getBoolean("showContinue", true);
    }

    private static List<String> split(String s) {
        List<String> out = new ArrayList<>();
        for (String part : s.split(",")) if (!part.isEmpty()) out.add(part);
        return out;
    }
}
