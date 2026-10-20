package local.tvhome;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.drawable.Drawable;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** One launchable TV app, with its artwork and glow colour worked out ahead of time. */
final class AppEntry {
    final String pkg;
    final ComponentName component;
    final String label;
    final Drawable banner;
    final Drawable icon;
    final int accent;

    private AppEntry(ResolveInfo ri, PackageManager pm) {
        ActivityInfo ai = ri.activityInfo;
        pkg = ai.packageName;
        component = new ComponentName(ai.packageName, ai.name);
        label = ri.loadLabel(pm).toString();
        banner = ai.loadBanner(pm);
        icon = ri.loadIcon(pm);
        accent = Ui.accent(banner != null ? banner : icon);
    }

    Intent launchIntent() {
        return new Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
                .setComponent(component)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
    }

    /** Every TV app except this one, sorted by name. Slow (loads artwork), so call it off the main thread. */
    static List<AppEntry> loadAll(Context c) {
        PackageManager pm = c.getPackageManager();
        Intent query = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER);
        List<AppEntry> apps = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (ResolveInfo ri : pm.queryIntentActivities(query, 0)) {
            String pkg = ri.activityInfo.packageName;
            if (pkg.equals(c.getPackageName()) || !seen.add(pkg)) continue;
            apps.add(new AppEntry(ri, pm));
        }
        apps.sort((a, b) -> a.label.compareToIgnoreCase(b.label));
        return apps;
    }
}
