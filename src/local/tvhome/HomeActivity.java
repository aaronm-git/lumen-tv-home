package local.tvhome;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Typeface;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.tv.TvContract;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.text.TextUtils;
import android.text.format.DateFormat;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.DecelerateInterpolator;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Supplier;

public class HomeActivity extends Activity {

    private static final String[] DEFAULT_FAVORITES = {
            "com.google.android.youtube.tv",
            "com.netflix.ninja",
            "com.amazon.amazonvideo.livingroom",
            "com.disney.disneyplus",
            "com.hulu.livingroomplus",
            "com.apple.atve.sony.appletv",
            "com.spotify.tv.android",
    };

    private static final String LIVE_TV = "com.sony.dtv.tvx";
    private static final int SIDE = 56;
    private static final int MAX_SHOWS = 10;

    private static final int AGENTS_WIDTH = 380;

    private static final int NOW_PLAYING_DELAY_MS = 1200;

    private final ExecutorService loader = Executors.newSingleThreadExecutor();
    private Prefs prefs;
    private List<AppEntry> apps = new ArrayList<>();

    private FrameLayout root;
    private FrameLayout content;
    private GlowBackground glow;
    private TextView greeting, clock, date, heroTitle, heroSub;

    private ScrollView pageScroll;
    private LinearLayout body;
    private LinearLayout firstRow;
    private boolean grid;
    private final List<TileView> tiles = new ArrayList<>();
    private final List<ShowTile> showTiles = new ArrayList<>();
    private boolean rendered;

    private WatchHistory history;
    private String shownShows = "";
    private boolean historyDirty;
    private boolean resumed;
    private boolean homePressed;
    private NowPlaying nowPlaying;
    private NowPlayingCard nowCard;
    private AgentStatus agents;
    private final AgentStatus.Listener agentsListener = this::onAgents;

    static boolean showing;
    private AgentsCard agentsCard;

    private Sheet chatSheet;
    private String chatId;

    private Sheet sheet;
    private String movingPkg;

    private final BroadcastReceiver clockReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context c, Intent i) {
            updateClock();
        }
    };

    private final WatchHistory.Listener historyListener = () -> {
        if (resumed && sheet == null && !showsKey(visibleShows()).equals(shownShows)) render(null);
        else historyDirty = true;
    };

    private final BroadcastReceiver packageReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context c, Intent i) {
            View f = getCurrentFocus();
            reload(f instanceof TileView ? ((TileView) f).app.pkg : null);
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        prefs = new Prefs(this, DEFAULT_FAVORITES);
        nowPlaying = new NowPlaying(this, this::onNowPlaying);
        agents = AgentStatus.get(this);
        history = WatchHistory.get(this);
        history.addListener(historyListener);
        buildLayout();
        setContentView(root);
        agents.addListener(agentsListener);

        IntentFilter pkgs = new IntentFilter();
        pkgs.addAction(Intent.ACTION_PACKAGE_ADDED);
        pkgs.addAction(Intent.ACTION_PACKAGE_REMOVED);
        pkgs.addAction(Intent.ACTION_PACKAGE_CHANGED);
        pkgs.addDataScheme("package");
        registerReceiver(packageReceiver, pkgs);

        reload(null);
    }

    @Override
    protected void onResume() {
        super.onResume();
        IntentFilter time = new IntentFilter(Intent.ACTION_TIME_TICK);
        time.addAction(Intent.ACTION_TIME_CHANGED);
        time.addAction(Intent.ACTION_TIMEZONE_CHANGED);
        registerReceiver(clockReceiver, time);
        updateClock();
        resumed = true;
        if (historyDirty) {
            historyDirty = false;
            render(null);
        }
        if (homePressed) {
            homePressed = false;
            goToStart();
        }
        if (prefs.showNowPlaying) nowPlaying.start();
        showing = true;

        if (agents.last == null) {
            closeChat();
            showAgentsCard(false);
        }
        if (prefs.showAgents) agents.want(AgentStatus.HOME, true);
    }

    @Override
    protected void onPause() {
        super.onPause();
        resumed = false;
        unregisterReceiver(clockReceiver);
        nowPlaying.stop();

        root.removeCallbacks(revealNowCard);
        if (nowCard.hasFocus()) goToStart();
        nowCard.setVisibility(View.GONE);
        showing = false;
        agents.want(AgentStatus.HOME, false);
    }

    @Override
    protected void onDestroy() {
        unregisterReceiver(packageReceiver);
        agents.removeListener(agentsListener);
        history.removeListener(historyListener);
        loader.shutdownNow();
        super.onDestroy();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        if (sheet != null) sheet.dismiss();
        if (movingPkg != null) finishMove();
        homePressed = true;
        goToStart();
    }

    @Override
    public void onBackPressed() {

        if (sheet != null) sheet.dismiss();
        else goToStart();
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent ev) {
        int key = ev.getKeyCode();
        boolean down = ev.getAction() == KeyEvent.ACTION_DOWN;
        if (movingPkg != null && sheet == null) {
            switch (key) {
                case KeyEvent.KEYCODE_DPAD_LEFT:
                case KeyEvent.KEYCODE_DPAD_RIGHT:
                    if (down) moveFavorite(key == KeyEvent.KEYCODE_DPAD_RIGHT ? 1 : -1);
                    return true;
                case KeyEvent.KEYCODE_DPAD_CENTER:
                case KeyEvent.KEYCODE_ENTER:
                case KeyEvent.KEYCODE_BACK:
                    if (!down) finishMove();
                    return true;
                case KeyEvent.KEYCODE_DPAD_UP:
                case KeyEvent.KEYCODE_DPAD_DOWN:
                    return true;
            }
        }
        if (key == KeyEvent.KEYCODE_MENU && down && sheet == null) {
            View f = getCurrentFocus();
            if (f instanceof TileView) {
                showOptions((TileView) f);
                return true;
            }
            if (f instanceof ShowTile) {
                showShowOptions((ShowTile) f);
                return true;
            }
        }
        return super.dispatchKeyEvent(ev);
    }

    private void buildLayout() {
        grid = "grid".equals(prefs.layout);
        root = new FrameLayout(this);
        glow = new GlowBackground(this);
        root.addView(glow, match());

        content = new FrameLayout(this);
        content.setClipChildren(false);
        content.setClipToPadding(false);
        root.addView(content, match());

        FrameLayout top = new FrameLayout(this);
        top.setClipChildren(false);
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.VERTICAL);
        greeting = text(17, 0xA6FFFFFF, "sans-serif");
        clock = text(64, 0xFFFFFFFF, "sans-serif-light");
        clock.setEllipsize(null);
        clock.setIncludeFontPadding(false);
        clock.setLetterSpacing(-0.02f);
        date = text(17, 0xB3FFFFFF, "sans-serif");
        header.addView(greeting);
        header.addView(clock, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        header.addView(date);
        FrameLayout.LayoutParams headerLp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP | Gravity.START);
        headerLp.leftMargin = dp(SIDE);
        top.addView(header, headerLp);

        LinearLayout pills = new LinearLayout(this);
        pills.setClipChildren(false);
        pills.addView(pill("Inputs", "Switch to HDMI or Live TV", this::showInputs));
        View settings = pill("Settings", "Layout and TV settings", this::showSettings);
        LinearLayout.LayoutParams gap = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        gap.leftMargin = dp(12);
        pills.addView(settings, gap);
        FrameLayout.LayoutParams pillsLp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP | Gravity.END);
        pillsLp.rightMargin = dp(SIDE);
        pillsLp.topMargin = dp(8);
        top.addView(pills, pillsLp);

        nowCard = new NowPlayingCard(this);
        nowCard.setVisibility(View.GONE);
        nowCard.body.setOnClickListener(v -> openNowPlaying());
        nowCard.button.setOnClickListener(v -> togglePlayback());
        nowCard.onFocused = this::nowPlayingHero;

        agentsCard = new AgentsCard(this);
        agentsCard.setVisibility(View.GONE);
        agentsCard.callbacks = new AgentsCard.Callbacks() {
            @Override
            public void onFocused(String title, String hint, int color) {
                setHero(title, hint, color);
            }

            @Override
            public void onSelected(AgentStatus.Chat chat) {
                showChat(chat);
            }
        };

        LinearLayout side = new LinearLayout(this);
        side.setOrientation(LinearLayout.VERTICAL);
        side.setGravity(Gravity.END);
        side.setClipChildren(false);
        side.addView(nowCard);
        LinearLayout.LayoutParams agentsLp = new LinearLayout.LayoutParams(
                dp(AGENTS_WIDTH), ViewGroup.LayoutParams.WRAP_CONTENT);
        agentsLp.topMargin = dp(12);
        side.addView(agentsCard, agentsLp);
        FrameLayout.LayoutParams sideLp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP | Gravity.END);
        sideLp.rightMargin = dp(SIDE);
        sideLp.topMargin = dp(68);
        sideLp.bottomMargin = dp(16);

        heroTitle = text(30, 0xFFFFFFFF, "sans-serif-medium");
        heroSub = text(14, 0x80FFFFFF, "sans-serif");

        pageScroll = new ScrollView(this);
        pageScroll.setVerticalScrollBarEnabled(false);
        pageScroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        pageScroll.setClipChildren(false);
        pageScroll.setVerticalFadingEdgeEnabled(true);
        pageScroll.setFadingEdgeLength(dp(40));

        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setClipChildren(false);
        page.setClipToPadding(false);
        page.setPadding(0, dp(36), 0, dp(32));
        LinearLayout left = new LinearLayout(this);
        left.setOrientation(LinearLayout.VERTICAL);
        left.setClipChildren(false);
        left.addView(top);
        LinearLayout.LayoutParams heroLp = indented(0);
        heroLp.topMargin = dp(28);
        left.addView(heroTitle, heroLp);
        left.addView(heroSub, indented(16));
        FrameLayout head = new FrameLayout(this);
        head.setClipChildren(false);
        head.addView(left, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        head.addView(side, sideLp);
        page.addView(head);

        body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setClipChildren(false);
        body.setClipToPadding(false);
        page.addView(body);

        pageScroll.addView(page);
        content.addView(pageScroll, match());
    }

    private HorizontalScrollView scroller(LinearLayout row) {
        HorizontalScrollView s = new HorizontalScrollView(this);
        s.setHorizontalScrollBarEnabled(false);
        s.setOverScrollMode(View.OVER_SCROLL_NEVER);
        s.setClipChildren(false);
        s.setClipToPadding(false);
        s.setHorizontalFadingEdgeEnabled(true);
        s.setFadingEdgeLength(dp(SIDE * 2));
        s.setPadding(0, dp(12), 0, dp(14));
        row.setClipChildren(false);
        row.setClipToPadding(false);
        row.setPadding(dp(SIDE), 0, dp(SIDE), 0);
        s.addView(row);
        return s;
    }

    private TextView text(float sp, int color, String family) {
        TextView t = new TextView(this);
        t.setTextSize(sp);
        t.setTextColor(color);
        t.setTypeface(Typeface.create(family, Typeface.NORMAL));
        t.setSingleLine();
        t.setEllipsize(TextUtils.TruncateAt.END);
        t.setShadowLayer(12, 0, 2, 0x66000000);
        return t;
    }

    private TextView sectionLabel(String label) {
        TextView t = text(12, 0x8CFFFFFF, "sans-serif-medium");
        t.setLetterSpacing(0.14f);
        t.setText(label);
        return t;
    }

    private View pill(String name, String hint, Runnable action) {
        TextView p = text(15, 0, "sans-serif-medium");
        p.setText(name);
        p.setTextColor(Ui.onPill(false));
        p.setShadowLayer(0, 0, 0, 0);
        p.setBackground(Ui.pill(dp(999)));
        p.setPadding(dp(18), dp(8), dp(18), dp(8));
        p.setFocusable(true);
        p.setClickable(true);
        p.setDefaultFocusHighlightEnabled(false);
        p.setOnClickListener(v -> action.run());
        p.setOnFocusChangeListener((v, has) -> {
            v.animate().scaleX(has ? 1.06f : 1f).scaleY(has ? 1.06f : 1f).setDuration(150).start();
            if (has) setHero(name, hint, Ui.SLATE);
        });
        return p;
    }

    private LinearLayout.LayoutParams indented(int bottomMargin) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = dp(SIDE);
        lp.bottomMargin = dp(bottomMargin);
        return lp;
    }

    private static FrameLayout.LayoutParams match() {
        return new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
    }

    private int dp(float v) {
        return Ui.dp(this, v);
    }

    private void updateClock() {
        Calendar now = Calendar.getInstance();
        clock.setText(DateFormat.format(DateFormat.is24HourFormat(this) ? "H:mm" : "h:mm", now));
        date.setText(DateFormat.format("EEEE, MMMM d", now));
        greeting.setText(greetingFor(now));
    }

    private String greetingFor(Calendar now) {
        int month = now.get(Calendar.MONTH), day = now.get(Calendar.DAY_OF_MONTH);
        int hour = now.get(Calendar.HOUR_OF_DAY);
        if (month == Calendar.OCTOBER && day == 31) return "Happy Halloween";
        if (month == Calendar.DECEMBER && day == 25) return "Merry Christmas";
        if (month == Calendar.JANUARY && day == 1) return "Happy New Year";
        if (hour < 5) return "Up late";
        if (hour < 12) return "Good morning";
        if (hour < 17) return "Good afternoon";
        return "Good evening";
    }

    private void reload(String focusPkg) {
        loader.execute(() -> {
            List<AppEntry> loaded = AppEntry.loadAll(this);
            runOnUiThread(() -> {
                if (isDestroyed()) return;
                apps = loaded;
                render(focusPkg);
            });
        });
    }

    private Map<String, AppEntry> appsByPkg() {
        Map<String, AppEntry> byPkg = new HashMap<>();
        for (AppEntry e : apps) byPkg.put(e.pkg, e);
        return byPkg;
    }

    private List<WatchHistory.Show> visibleShows() {
        List<WatchHistory.Show> out = new ArrayList<>();
        if (!prefs.showContinue) return out;
        Map<String, AppEntry> byPkg = appsByPkg();
        for (WatchHistory.Show sh : history.list()) {
            if (byPkg.containsKey(sh.pkg) && !sh.finished()) out.add(sh);
            if (out.size() == MAX_SHOWS) break;
        }
        return out;
    }

    private static String showsKey(List<WatchHistory.Show> shows) {
        StringBuilder b = new StringBuilder();
        for (WatchHistory.Show sh : shows) b.append(sh.id).append(sh.title).append(sh.subtitle).append('\n');
        return b.toString();
    }

    private List<AppEntry> visibleFavorites() {
        Map<String, AppEntry> byPkg = appsByPkg();
        List<AppEntry> out = new ArrayList<>();
        for (String pkg : prefs.favorites) {
            AppEntry e = byPkg.get(pkg);
            if (e != null) out.add(e);
        }
        return out;
    }

    private void render(String focusPkg) {
        View focused = getCurrentFocus();
        TileView was = focused instanceof TileView ? (TileView) focused : null;
        ShowTile wasShow = focused instanceof ShowTile ? (ShowTile) focused : null;
        int oldIndex = tiles.indexOf(focused);
        int oldShowIndex = showTiles.indexOf(focused);
        int keepSection = was != null ? was.section : TileView.FAVORITE;

        List<AppEntry> favs = visibleFavorites();
        List<AppEntry> others = new ArrayList<>();
        for (AppEntry e : apps) {
            if (!prefs.favorites.contains(e.pkg) && !prefs.hidden.contains(e.pkg)) others.add(e);
        }
        List<WatchHistory.Show> shows = visibleShows();
        shownShows = showsKey(shows);
        historyDirty = false;

        tiles.clear();
        showTiles.clear();
        firstRow = null;
        body.removeAllViews();
        if (prefs.showContinue) {
            if (shows.isEmpty()) {
                body.addView(sectionLabel("CONTINUE WATCHING  ·  SHOWS YOU PLAY WILL APPEAR HERE"), indented(18));
            } else {
                showSection(shows);
            }
        }
        if (grid) {
            List<AppEntry> all = new ArrayList<>(favs);
            all.addAll(others);
            if (!all.isEmpty()) gridSection("APPS", all, favs.size());
        } else {
            if (favs.isEmpty()) body.addView(sectionLabel("FAVORITES  ·  HOLD OK ON AN APP TO ADD IT"), indented(18));
            else rowSection("FAVORITES", favs, TileView.FAVORITE, dp(192), dp(108), dp(22));
            if (!others.isEmpty()) rowSection("APPS", others, TileView.APP, dp(136), dp(77), dp(16));
        }

        boolean focusElsewhere = rendered && was == null && wasShow == null && focusPkg == null
                && getCurrentFocus() != null;
        rendered = true;
        if (sheet != null || focusElsewhere) return;
        View target = null;
        if (wasShow != null && focusPkg == null) {
            target = findShow(wasShow.show.id);
            if (target == null && !showTiles.isEmpty()) {
                target = showTiles.get(Math.min(oldShowIndex, showTiles.size() - 1));
            }
        }
        if (target == null) target = findTile(focusPkg, keepSection);
        if (target == null && oldIndex >= 0 && !tiles.isEmpty()) target = tiles.get(Math.min(oldIndex, tiles.size() - 1));
        if (target == null) target = firstTile();
        if (target != null) target.requestFocus();
    }

    private void showSection(List<WatchHistory.Show> shows) {
        body.addView(sectionLabel("CONTINUE WATCHING"), indented(0));
        LinearLayout row = new LinearLayout(this);
        body.addView(scroller(row));
        firstRow = row;
        int cols = 4, gap = dp(24);
        int w = (getResources().getDisplayMetrics().widthPixels - 2 * dp(SIDE) - (cols - 1) * gap) / cols;
        int h = w * 9 / 16;
        Map<String, AppEntry> byPkg = appsByPkg();
        for (WatchHistory.Show sh : shows) row.addView(showTile(sh, byPkg.get(sh.pkg), w, h, gap));
    }

    private ShowTile showTile(WatchHistory.Show sh, AppEntry app, int w, int h, int gap) {
        int accent = history.accent(sh);
        ShowTile t = new ShowTile(this, sh, history.art(sh), accent != 0 ? accent : app.accent, app, w, h);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(w, h);
        lp.rightMargin = gap;
        t.setLayoutParams(lp);
        t.setOnClickListener(v -> openPlayer(NowPlaying.find(this, sh.pkg, sh.title), sh.pkg));
        t.setOnLongClickListener(v -> {
            showShowOptions(t);
            return true;
        });
        t.setOnFocusChangeListener((v, has) -> {
            if (!has) return;
            List<String> hint = new ArrayList<>();
            if (sh.subtitle != null) hint.add(sh.subtitle);
            hint.add(app.label);
            String left = timeLeft(sh);
            if (left != null) hint.add(left);
            setHero(sh.title, String.join("  ·  ", hint), t.accent);
            if (t.getParent() == firstRow) pageScroll.post(() -> pageScroll.smoothScrollTo(0, 0));
        });
        showTiles.add(t);
        return t;
    }

    private static String timeLeft(WatchHistory.Show sh) {
        if (sh.duration <= 0 || sh.position < 0) return null;
        long mins = Math.max(0, sh.duration - sh.position) / 60_000;
        if (mins < 1) return "Almost done";
        if (mins < 60) return mins + " min left";
        return mins / 60 + " h " + mins % 60 + " min left";
    }

    private ShowTile findShow(String id) {
        for (ShowTile t : showTiles) if (t.show.id.equals(id)) return t;
        return null;
    }

    private View firstTile() {
        if (!showTiles.isEmpty()) return showTiles.get(0);
        return tiles.isEmpty() ? null : tiles.get(0);
    }

    private void rowSection(String label, List<AppEntry> list, int section, int w, int h, int gap) {
        body.addView(sectionLabel(label), indented(0));
        LinearLayout row = new LinearLayout(this);
        body.addView(scroller(row));
        if (firstRow == null) firstRow = row;
        for (AppEntry e : list) row.addView(tile(e, section, w, h, gap));
    }

    private void gridSection(String label, List<AppEntry> list, int favCount) {
        body.addView(sectionLabel(label), indented(0));
        int cols = 5, gap = dp(24);
        int w = (getResources().getDisplayMetrics().widthPixels - 2 * dp(SIDE) - (cols - 1) * gap) / cols;
        int h = w * 9 / 16;
        LinearLayout row = null;
        for (int i = 0; i < list.size(); i++) {
            if (i % cols == 0) {
                row = new LinearLayout(this);
                row.setClipChildren(false);
                row.setClipToPadding(false);
                row.setPadding(dp(SIDE), dp(12), dp(SIDE), dp(16));
                body.addView(row);
                if (firstRow == null) firstRow = row;
            }
            int sec = i < favCount ? TileView.FAVORITE : TileView.APP;
            row.addView(tile(list.get(i), sec, w, h, i % cols == cols - 1 ? 0 : gap));
        }
    }

    private TileView tile(AppEntry e, int section, int w, int h, int gap) {
        TileView t = new TileView(this, e, section, w, h);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(w, h);
        lp.rightMargin = gap;
        t.setLayoutParams(lp);
        t.setOnClickListener(v -> start(e.launchIntent()));
        t.setOnLongClickListener(v -> {
            showOptions(t);
            return true;
        });
        boolean moving = section == TileView.FAVORITE && e.pkg.equals(movingPkg);
        t.setOnFocusChangeListener((v, has) -> {
            if (!has) return;
            String hint = moving ? "Use ◀ ▶ to move  ·  OK when done"
                    : section == TileView.FAVORITE ? "Favorite  ·  hold OK for options"
                    : "Hold OK to add to Favorites";
            setHero(e.label, hint, e.accent);

            if (t.getParent() == firstRow) pageScroll.post(() -> pageScroll.smoothScrollTo(0, 0));
        });
        t.setMoving(moving);
        tiles.add(t);
        return t;
    }

    private TileView findTile(String pkg, int section) {
        if (pkg == null) return null;
        TileView fallback = null;
        for (TileView t : tiles) {
            if (!t.app.pkg.equals(pkg)) continue;
            if (t.section == section) return t;
            if (fallback == null) fallback = t;
        }
        return fallback;
    }

    private void setHero(String title, String sub, int accent) {
        heroTitle.setText(title);
        heroSub.setText(sub);
        glow.setAccent(accent);
    }

    private void goToStart() {
        pageScroll.smoothScrollTo(0, 0);
        View first = firstTile();
        if (first != null) first.requestFocus();
    }

    private void start(Intent intent) {
        try {
            startActivity(intent);
        } catch (ActivityNotFoundException | SecurityException ex) {
            Toast.makeText(this, "Couldn't open that", Toast.LENGTH_SHORT).show();
        }
    }

    private void showOptions(TileView t) {
        AppEntry e = t.app;
        boolean favorite = prefs.favorites.contains(e.pkg);
        Sheet s = new Sheet(e.label);
        if (favorite) {
            s.add("Remove from Favorites", null, false, () -> {
                prefs.favorites.remove(e.pkg);
                prefs.save();
                render(e.pkg);
            });
            if (t.section == TileView.FAVORITE && visibleFavorites().size() > 1) s.add("Move", null, false, () -> {
                movingPkg = e.pkg;
                render(e.pkg);
            });
        } else {
            s.add("Add to Favorites", null, false, () -> {
                prefs.favorites.add(e.pkg);
                prefs.save();
                render(e.pkg);
            });
            s.add("Hide", "Bring it back from Settings", false, () -> {
                prefs.hidden.add(e.pkg);
                prefs.save();
                render(null);
            });
        }
        s.add("App info", null, false, () -> start(new Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + e.pkg))));
        s.show();
    }

    private void showShowOptions(ShowTile t) {
        WatchHistory.Show sh = t.show;
        Sheet s = new Sheet(sh.title);
        s.add("Remove from Continue watching", null, false, () -> history.remove(sh));
        s.add("Open " + t.app.label, null, false, () -> start(t.app.launchIntent()));
        s.add("Clear Continue watching", "Removes every show from the row", false, history::clear);
        s.show();
    }

    private void showSettings() {
        Sheet s = new Sheet("Settings");
        s.choice(() -> grid ? "Rows" : "Rows  ✓", () -> "Favorites on top, every other app below",
                () -> setLayout("rows"));
        s.choice(() -> grid ? "Grid  ✓" : "Grid", () -> "Every app in one grid, like Apple TV",
                () -> setLayout("grid"));
        s.choice(() -> "Continue watching", () -> !prefs.showContinue ? "Off"
                : nowPlaying.allowed() ? "On  ·  shows and movies you've played" : "On  ·  waiting for permission",
                () -> {
            prefs.showContinue = !prefs.showContinue;
            prefs.save();
            render(null);
        });
        s.choice(() -> "Now playing", () -> !prefs.showNowPlaying ? "Off"
                : nowPlaying.allowed() ? "On  ·  what's playing or paused" : "On  ·  waiting for permission", () -> {
            prefs.showNowPlaying = !prefs.showNowPlaying;
            prefs.save();
            if (prefs.showNowPlaying) {
                nowPlaying.start();
            } else {
                nowPlaying.stop();
                onNowPlaying(null, null, false);
            }
        });
        s.choice(() -> "Agents", this::agentsSetting, () -> {
            prefs.showAgents = !prefs.showAgents;
            prefs.save();
            agents.want(AgentStatus.HOME, prefs.showAgents);
            if (prefs.showAgents && agents.last != null) onAgents(agents.last);
            else showAgentsCard(false);
        });
        s.choice(() -> "Agent notifications", () -> prefs.agentAlerts
                ? "On  ·  a chat's title over other apps when it finishes or needs you" : "Off", () -> {
            prefs.agentAlerts = !prefs.agentAlerts;
            prefs.save();
        });
        View pairAgain = s.add("Pair again", "Forget the key and show a new code to type on the Mac",
                false, agents::pairAgain);
        s.update(() -> pairAgain.setVisibility(prefs.showAgents ? View.VISIBLE : View.GONE));
        if (!history.list().isEmpty()) {
            s.add("Clear watch history", "Removes every show from Continue watching", false, history::clear);
        }
        if (!prefs.hidden.isEmpty()) {
            s.add("Hidden apps (" + prefs.hidden.size() + ")", "Show apps you've hidden", false, this::showHidden);
        }
        s.add("TV settings", "Picture, sound, network and more", false,
                () -> start(new Intent(Settings.ACTION_SETTINGS)));
        s.add("Licenses & notices", "Lumen, the model logos and trademarks", false, this::showNotices);
        s.show();
    }

    private void showNotices() {
        Sheet s = new Sheet("Licenses & notices");
        s.notice("Lumen", getString(R.string.notice_lumen));
        s.notice("Model logos", getString(R.string.notice_logos));
        s.notice("Trademarks", getString(R.string.notice_trademarks));
        s.notice("MIT License", getString(R.string.notice_mit));
        s.show();
    }

    private void setLayout(String layout) {
        if (layout.equals(prefs.layout)) return;
        prefs.layout = layout;
        prefs.save();
        grid = "grid".equals(layout);
        render(null);
    }

    private void showHidden() {
        Sheet s = new Sheet("Hidden apps");
        Map<String, String> labels = new HashMap<>();
        for (AppEntry e : apps) labels.put(e.pkg, e.label);
        for (String pkg : new ArrayList<>(prefs.hidden)) {
            String label = labels.get(pkg);
            s.add(label != null ? label : pkg, "Select to show it again", false, () -> {
                prefs.hidden.remove(pkg);
                prefs.save();
                render(pkg);
            });
        }
        s.show();
    }

    private void moveFavorite(int direction) {
        List<AppEntry> shown = visibleFavorites();
        int i = -1;
        for (int k = 0; k < shown.size(); k++) if (shown.get(k).pkg.equals(movingPkg)) i = k;
        int j = i + direction;
        if (i < 0 || j < 0 || j >= shown.size()) return;
        int a = prefs.favorites.indexOf(movingPkg), b = prefs.favorites.indexOf(shown.get(j).pkg);
        prefs.favorites.set(a, shown.get(j).pkg);
        prefs.favorites.set(b, movingPkg);
        prefs.save();
        render(movingPkg);
    }

    private void finishMove() {
        String pkg = movingPkg;
        movingPkg = null;
        render(pkg);
    }

    private void onNowPlaying(MediaController c, MediaMetadata md, boolean playing) {
        root.removeCallbacks(revealNowCard);
        if (c == null || !prefs.showNowPlaying) {
            if (nowCard.hasFocus()) goToStart();
            nowCard.setVisibility(View.GONE);
            return;
        }
        nowCard.bind(c, md, playing);
        if (nowCard.getVisibility() == View.VISIBLE) {
            if (nowCard.hasFocus()) nowPlayingHero();
        } else {
            root.postDelayed(revealNowCard, NOW_PLAYING_DELAY_MS);
        }
    }

    private final Runnable revealNowCard = () -> {
        nowCard.setVisibility(View.VISIBLE);
        nowCard.setAlpha(0f);
        nowCard.setTranslationX(dp(16));
        nowCard.animate().alpha(1f).translationX(0).setDuration(350).setInterpolator(new DecelerateInterpolator())
                .start();
    };

    private void nowPlayingHero() {
        String hint = nowCard.button.isFocused() ? (nowCard.playing ? "Pause" : "Play")
                : (nowCard.playing ? "Playing in " : "Paused in ") + nowCard.appName + "  ·  OK to open";
        setHero(nowCard.titleText, hint, nowCard.accent);
    }

    private void openNowPlaying() {
        MediaController c = nowCard.controller;
        if (c != null) openPlayer(c, c.getPackageName());
    }

    private void openPlayer(MediaController c, String pkg) {
        PendingIntent player = c != null ? c.getSessionActivity() : null;
        if (player != null) {
            try {
                player.send();
                return;
            } catch (PendingIntent.CanceledException ignored) {

            }
        }
        Intent launch = getPackageManager().getLeanbackLaunchIntentForPackage(pkg);
        if (launch != null) start(launch);
    }

    private void togglePlayback() {
        MediaController c = nowCard.controller;
        if (c == null) return;
        if (nowCard.playing) c.getTransportControls().pause();
        else c.getTransportControls().play();
    }

    private void onAgents(AgentStatus.Snapshot s) {
        if (!prefs.showAgents) return;
        if (chatSheet != null && !(s.active() && listed(s, chatId))) closeChat();
        boolean focused = agentsCard.hasFocus();
        boolean show = prefs.showAgents && agentsCard.bind(s);
        showAgentsCard(show);

        if (focused && show && !agentsCard.hasFocus()) goToStart();
    }

    private static boolean listed(AgentStatus.Snapshot s, String id) {
        for (AgentStatus.Chat c : s.chats) if (c.id.equals(id)) return true;
        return false;
    }

    private void closeChat() {
        if (chatSheet != null) chatSheet.dismiss();
        chatSheet = null;
        chatId = null;
    }

    private void showAgentsCard(boolean show) {
        if (!show && agentsCard.hasFocus()) goToStart();
        agentsCard.setVisibility(show ? View.VISIBLE : View.GONE);

        int max = show ? getResources().getDisplayMetrics().widthPixels - dp(2 * SIDE + AGENTS_WIDTH + 24)
                : Integer.MAX_VALUE;
        heroTitle.setMaxWidth(max);
        heroSub.setMaxWidth(max);
    }

    private String agentsSetting() {

        if (!prefs.showAgents) return "Off  ·  shows T3 Code chats from a Mac running Lumen Agents";
        AgentStatus.Snapshot s = agents.last;
        if (s != null && s.phase == AgentStatus.PAIRING) return "On  ·  pair with code " + AgentStatus.grouped(s.code);
        String from = agents.paired() && s != null ? s.mac : "your Mac (Lumen Agents)";
        return "On  ·  chat titles, projects and replies from " + from;
    }

    private void showChat(AgentStatus.Chat c) {
        Sheet s = new Sheet(c.title);
        List<String> about = new ArrayList<>();
        about.add(AgentsCard.stateName(c.state));
        if (!c.detail.isEmpty() && !c.detail.equals("Working") && !c.detail.equals("Finished")) about.add(c.detail);
        if (!c.project.isEmpty()) about.add(c.project);
        if (!c.model.isEmpty()) about.add(AgentsCard.modelName(c.model));
        if (c.age >= 60) about.add(AgentsCard.ago(c.age) + ("working".equals(c.state) ? "" : " ago"));
        s.note(String.join("  ·  ", about), AgentsCard.color(c.state));
        if (c.text != null) s.note(c.text, 0xCCFFFFFF);
        s.add("Close", "Reply in T3 Code on your Mac or phone", false, () -> {});
        s.show();
        chatSheet = s;
        chatId = c.id;
    }

    private void showInputs() {
        Sheet s = new Sheet("Inputs");
        Intent live = getPackageManager().getLeanbackLaunchIntentForPackage(LIVE_TV);
        if (live != null) s.add("Live TV", "Antenna channels", false, () -> start(live));

        TvInputManager tim = (TvInputManager) getSystemService(Context.TV_INPUT_SERVICE);
        if (tim != null) {
            List<TvInputInfo> all = tim.getTvInputList();
            Map<String, TvInputInfo> byId = new HashMap<>();
            Set<String> parents = new HashSet<>();
            for (TvInputInfo info : all) {
                byId.put(info.getId(), info);
                if (info.getParentId() != null) parents.add(info.getParentId());
            }
            List<TvInputInfo> ports = new ArrayList<>();
            for (TvInputInfo info : all) {

                if (info.isPassthroughInput() && !parents.contains(info.getId())) ports.add(info);
            }
            ports.sort((x, y) -> Integer.compare(state(tim, x, byId), state(tim, y, byId)));
            for (TvInputInfo info : ports) {
                int st = state(tim, info, byId);
                TvInputInfo parent = info.getParentId() != null ? byId.get(info.getParentId()) : null;
                String status = st == TvInputManager.INPUT_STATE_CONNECTED ? "Connected"
                        : st == TvInputManager.INPUT_STATE_CONNECTED_STANDBY ? "Standby" : "Nothing plugged in";
                String detail = parent != null ? label(parent) + "  ·  " + status : status;
                s.add(label(info), detail, st == TvInputManager.INPUT_STATE_DISCONNECTED, () -> start(
                        new Intent(Intent.ACTION_VIEW, TvContract.buildChannelUriForPassthroughInput(info.getId()))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)));
            }
        }
        s.show();
    }

    private static int state(TvInputManager tim, TvInputInfo info, Map<String, TvInputInfo> byId) {
        int st = tim.getInputState(info.getId());
        TvInputInfo parent = info.getParentId() != null ? byId.get(info.getParentId()) : null;
        return parent != null ? Math.min(st, tim.getInputState(parent.getId())) : st;
    }

    private String label(TvInputInfo info) {
        CharSequence custom = info.loadCustomLabel(this);
        return (TextUtils.isEmpty(custom) ? info.loadLabel(this) : custom).toString();
    }

    private final class Sheet {
        private final FrameLayout scrim = new FrameLayout(HomeActivity.this);
        private final LinearLayout list = new LinearLayout(HomeActivity.this);
        private final ScrollView scroll = new ScrollView(HomeActivity.this);
        private final View restoreFocus = getCurrentFocus();
        private final List<Runnable> updates = new ArrayList<>();

        Sheet(String title) {
            scrim.setBackgroundColor(0xB3000000);
            LinearLayout card = new LinearLayout(HomeActivity.this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setBackground(Ui.card(HomeActivity.this));
            card.setPadding(dp(16), dp(20), dp(16), dp(16));
            TextView t = text(20, 0xFFFFFFFF, "sans-serif-medium");
            t.setText(title);
            t.setPadding(dp(16), 0, dp(16), dp(8));
            card.addView(t);
            list.setOrientation(LinearLayout.VERTICAL);
            scroll.setVerticalScrollBarEnabled(false);
            scroll.addView(list);
            card.addView(scroll);
            scrim.addView(card, new FrameLayout.LayoutParams(
                    dp(400), ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER));
        }

        void note(String text, int color) {
            TextView t = text(14, color, "sans-serif");
            t.setShadowLayer(0, 0, 0, 0);
            t.setSingleLine(false);
            t.setMaxLines(8);
            t.setLineSpacing(0, 1.15f);
            t.setText(text);
            t.setPadding(dp(16), dp(4), dp(16), dp(6));
            list.addView(t);
        }

        void choice(Supplier<String> title, Supplier<String> detail, Runnable action) {
            LinearLayout item = add(title.get(), detail.get(), false, false, () -> {
                action.run();
                for (Runnable update : updates) update.run();
            });
            update(() -> {
                ((TextView) item.getChildAt(0)).setText(title.get());
                ((TextView) item.getChildAt(1)).setText(detail.get());
            });
        }

        void update(Runnable update) {
            updates.add(update);
            update.run();
        }

        LinearLayout add(String title, String detail, boolean dim, Runnable action) {
            return add(title, detail, dim, true, action);
        }

        private LinearLayout add(String title, String detail, boolean dim, boolean close, Runnable action) {
            LinearLayout item = new LinearLayout(HomeActivity.this);
            item.setOrientation(LinearLayout.VERTICAL);
            item.setFocusable(true);
            item.setClickable(true);
            item.setDefaultFocusHighlightEnabled(false);
            item.setBackground(Ui.pill(dp(12)));
            item.setPadding(dp(16), dp(10), dp(16), dp(10));
            TextView a = text(16, 0, "sans-serif-medium");
            a.setShadowLayer(0, 0, 0, 0);
            a.setText(title);
            a.setTextColor(Ui.onPill(dim));
            a.setDuplicateParentStateEnabled(true);
            item.addView(a);
            if (detail != null) {
                TextView b = text(12, 0, "sans-serif");
                b.setShadowLayer(0, 0, 0, 0);
                b.setSingleLine(false);
                b.setMaxLines(2);
                b.setText(detail);
                b.setTextColor(Ui.onPillDetail());
                b.setDuplicateParentStateEnabled(true);
                item.addView(b);
            }
            item.setOnClickListener(v -> {
                if (close) dismiss();
                action.run();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.topMargin = dp(6);
            list.addView(item, lp);
            return item;
        }

        void notice(String title, String text) {
            add(title, text, false, () -> {});
            TextView b = (TextView) ((ViewGroup) list.getChildAt(list.getChildCount() - 1)).getChildAt(1);
            b.setMaxLines(Integer.MAX_VALUE);
            b.setLineSpacing(0, 1.15f);
        }

        void show() {
            list.measure(View.MeasureSpec.makeMeasureSpec(dp(368), View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.UNSPECIFIED);
            if (list.getChildCount() > 6 || list.getMeasuredHeight() > dp(420)) {
                scroll.setLayoutParams(new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, dp(340)));
            }
            sheet = this;
            content.setDescendantFocusability(ViewGroup.FOCUS_BLOCK_DESCENDANTS);
            root.addView(scrim, match());
            scrim.setAlpha(0f);
            scrim.animate().alpha(1f).setDuration(140).start();
            for (int i = 0; i < list.getChildCount(); i++) if (list.getChildAt(i).requestFocus()) break;
        }

        void dismiss() {

            if (chatSheet == this) {
                chatSheet = null;
                chatId = null;
            }
            if (sheet != this) return;
            sheet = null;
            root.removeView(scrim);
            content.setDescendantFocusability(ViewGroup.FOCUS_AFTER_DESCENDANTS);
            if (restoreFocus != null && restoreFocus.isAttachedToWindow()) restoreFocus.requestFocus();
        }
    }
}
