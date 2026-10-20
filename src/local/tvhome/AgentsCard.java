package local.tvhome;

import android.content.Context;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.animation.DecelerateInterpolator;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Your T3 Code chats from the Mac: working, waiting for you, done or failed. New ones slide in. */
final class AgentsCard extends LinearLayout {
    private static final int MAX_ROWS = 3;

    interface Callbacks {
        void onFocused(String title, String hint, int color);

        void onSelected(AgentStatus.Chat chat);
    }

    Callbacks callbacks;
    private final TextView label;
    private final List<Row> rows = new ArrayList<>();
    /** The state each chat had when it was last shown, so only new ones and changes animate. */
    private final Map<String, String> shownStates = new HashMap<>();

    AgentsCard(Context c) {
        super(c);
        setOrientation(VERTICAL);
        setClipChildren(false);
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(Ui.dp(c, 16));
        bg.setColor(0x1AFFFFFF);
        setBackground(bg);
        setPadding(Ui.dp(c, 6), Ui.dp(c, 8), Ui.dp(c, 6), Ui.dp(c, 6));

        label = text(c, 11, 0x80FFFFFF, "sans-serif-medium");
        label.setLetterSpacing(0.12f);
        label.setPadding(Ui.dp(c, 10), 0, Ui.dp(c, 10), Ui.dp(c, 4));
        addView(label);
    }

    /** Shows the snapshot; returns false when there's nothing worth showing (no active chats). */
    boolean bind(AgentStatus.Snapshot s) {
        List<Line> lines = new ArrayList<>();
        String head;
        if (s.phase == AgentStatus.SEARCHING) {
            return false;
        } else if (s.phase == AgentStatus.OFFLINE) {
            head = "AGENTS";
            lines.add(new Line("offline", "Mac offline", "", 0x66FFFFFF, null,
                    "Lumen can't reach Lumen Agents on " + s.mac));
        } else if (s.phase == AgentStatus.PAIRING) {
            head = "AGENTS  ·  PAIR WITH " + s.mac.toUpperCase(Locale.ROOT);
            String code = s.code == null || s.code.length() != 6 ? s.code : s.code.substring(0, 3) + " " + s.code.substring(3);
            lines.add(new Line("pair", code, "On the Mac:  lumen-agents pair " + s.code, 0xFFFFFFFF, null,
                    "Pair with " + s.mac + ": run  lumen-agents pair " + s.code + "  in Terminal"));
        } else if (!"ok".equals(s.t3)) {
            head = "AGENTS";
            lines.add(new Line("t3", "offline".equals(s.t3) ? "T3 Code isn't running" : "T3 Code needs a new token",
                    "", 0x66FFFFFF, null, "on " + s.mac));
        } else if (s.chats.isEmpty()) {
            shownStates.clear();
            return false;
        } else {
            head = "AGENTS  ·  " + summary(s.chats);
            for (int i = 0; i < Math.min(MAX_ROWS, s.chats.size()); i++) {
                AgentStatus.Chat chat = s.chats.get(i);
                lines.add(new Line(chat.id, chat.title, status(chat), color(chat.state), chat, hint(chat)));
            }
            if (s.chats.size() > MAX_ROWS) head += "  ·  +" + (s.chats.size() - MAX_ROWS) + " MORE";
        }
        label.setText(head);
        show(lines);
        Map<String, String> now = new HashMap<>();
        for (int i = 0; i < lines.size(); i++) {
            AgentStatus.Chat chat = lines.get(i).chat;
            if (chat == null) continue;
            now.put(chat.id, chat.state);
            if (!chat.state.equals(shownStates.get(chat.id))) rows.get(i).slideIn();
        }
        shownStates.clear();
        shownStates.putAll(now);
        return true;
    }

    private void show(List<Line> lines) {
        // Keep focus on the same chat (or the same spot) as rows are reused.
        int focusedRow = -1;
        String focusedKey = null;
        for (int i = 0; i < rows.size(); i++) {
            if (rows.get(i).hasFocus()) {
                focusedRow = i;
                focusedKey = rows.get(i).line.key;
            }
        }
        while (rows.size() < lines.size()) {
            Row r = new Row(getContext());
            rows.add(r);
            addView(r, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT));
        }
        while (rows.size() > lines.size()) removeView(rows.remove(rows.size() - 1));
        int moveTo = -1;
        for (int i = 0; i < lines.size(); i++) {
            rows.get(i).bind(lines.get(i));
            if (lines.get(i).key.equals(focusedKey)) moveTo = i;
        }
        if (focusedRow >= 0 && !rows.isEmpty()) {
            Row target = rows.get(moveTo >= 0 ? moveTo : Math.min(focusedRow, rows.size() - 1));
            if (target.isFocusable()) {
                if (!target.isFocused()) target.requestFocus();
                else target.announce();
            }
        }
    }

    /** The model maker's logo, or 0 if it's one we don't have. */
    static int icon(String brand) {
        switch (brand) {
            case "claude": return R.drawable.brand_claude;
            case "openai": return R.drawable.brand_openai;
            case "grok": return R.drawable.brand_grok;
            case "gemini": return R.drawable.brand_gemini;
            case "cursor": return R.drawable.brand_cursor;
            case "opencode": return R.drawable.brand_opencode;
            default: return 0;
        }
    }

    /** One-colour logos follow the text colour; Claude and Gemini keep their own. */
    static boolean tinted(String brand) {
        return !"claude".equals(brand) && !"gemini".equals(brand);
    }

    static int color(String state) {
        switch (state) {
            case "waiting": return 0xFFF5B54A;
            case "done": return 0xFF4FD08F;
            case "failed": return 0xFFF06B7E;
            default: return 0xFF5AA9F0;
        }
    }

    static String stateName(String state) {
        switch (state) {
            case "waiting": return "Waiting for you";
            case "done": return "Done";
            case "failed": return "Failed";
            default: return "Working";
        }
    }

    private static String status(AgentStatus.Chat c) {
        if ("working".equals(c.state) && c.age >= 60) return "Working  ·  " + ago(c.age);
        if ("done".equals(c.state) && c.age >= 60) return "Done  ·  " + ago(c.age) + " ago";
        return stateName(c.state);
    }

    static String hint(AgentStatus.Chat c) {
        List<String> parts = new ArrayList<>();
        parts.add(stateName(c.state));
        if (!c.detail.isEmpty() && !c.detail.equals("Working") && !c.detail.equals("Finished")) parts.add(c.detail);
        if (!c.project.isEmpty()) parts.add(c.project);
        if (!c.model.isEmpty()) parts.add(modelName(c.model));
        if (c.age >= 60) parts.add(ago(c.age) + ("working".equals(c.state) ? "" : " ago"));
        return String.join("  ·  ", parts) + "  ·  OK for details";
    }

    /** "claude-opus-5-5" → "Claude Opus 5.5", "gpt-6.1-sol" → "GPT-6.1 Sol". */
    static String modelName(String id) {
        StringBuilder b = new StringBuilder();
        boolean lastNumber = false;
        for (String w : id.split("-")) {
            if (w.isEmpty()) continue;
            boolean number = w.matches("[0-9.]+");
            if (number && lastNumber) {
                b.append('.').append(w);
            } else {
                if (b.length() > 0) b.append(number && b.toString().endsWith("GPT") ? "-" : " ");
                b.append(w.equals("gpt") ? "GPT" : Character.toUpperCase(w.charAt(0)) + w.substring(1));
            }
            lastNumber = number;
        }
        return b.toString();
    }

    static String ago(long secs) {
        long m = secs / 60;
        if (m < 60) return Math.max(1, m) + " min";
        if (m < 24 * 60) return m / 60 + " h";
        return m / (24 * 60) + " d";
    }

    private static String summary(List<AgentStatus.Chat> chats) {
        int[] n = new int[4];
        String[] order = {"waiting", "failed", "done", "working"};
        for (AgentStatus.Chat c : chats) {
            for (int i = 0; i < order.length; i++) if (order[i].equals(c.state)) n[i]++;
        }
        String[] names = {" WAITING", " FAILED", " DONE", " WORKING"};
        List<String> parts = new ArrayList<>();
        for (int i = 0; i < order.length; i++) if (n[i] > 0) parts.add(n[i] + names[i]);
        return String.join("  ·  ", parts);
    }

    private static TextView text(Context c, float sp, int color, String family) {
        TextView t = new TextView(c);
        t.setTextSize(sp);
        t.setTextColor(color);
        t.setTypeface(Typeface.create(family, Typeface.NORMAL));
        t.setSingleLine();
        t.setEllipsize(TextUtils.TruncateAt.END);
        return t;
    }

    private static final class Line {
        final String key, title, status, hint;
        final int color;
        final AgentStatus.Chat chat;

        Line(String key, String title, String status, int color, AgentStatus.Chat chat, String hint) {
            this.key = key;
            this.title = title;
            this.status = status;
            this.color = color;
            this.chat = chat;
            this.hint = hint;
        }
    }

    /**
     * One chat: the model's logo, its title, and a dot in the state's colour beside the state. White when focused,
     * like the other pills.
     */
    private final class Row extends LinearLayout {
        final ImageView logo;
        final View dot, stateDot;
        final TextView title, state;
        Line line;

        Row(Context c) {
            super(c);
            setOrientation(HORIZONTAL);
            setGravity(Gravity.CENTER_VERTICAL);
            setDefaultFocusHighlightEnabled(false);
            GradientDrawable on = new GradientDrawable();
            on.setCornerRadius(Ui.dp(c, 11));
            on.setColor(0xFFFFFFFF);
            StateListDrawable bg = new StateListDrawable();
            bg.addState(new int[]{android.R.attr.state_focused}, on);
            setBackground(bg);
            setPadding(Ui.dp(c, 10), Ui.dp(c, 5), Ui.dp(c, 10), Ui.dp(c, 5));

            logo = new ImageView(c);
            logo.setDuplicateParentStateEnabled(true);
            LayoutParams llp = new LayoutParams(Ui.dp(c, 16), Ui.dp(c, 16));
            llp.rightMargin = Ui.dp(c, 9);
            addView(logo, llp);

            dot = dot(c);
            LayoutParams dlp = new LayoutParams(Ui.dp(c, 8), Ui.dp(c, 8));
            dlp.leftMargin = Ui.dp(c, 4);
            dlp.rightMargin = Ui.dp(c, 13);
            addView(dot, dlp);

            title = text(c, 14, 0, "sans-serif-medium");
            title.setTextColor(Ui.onPill(false));
            title.setDuplicateParentStateEnabled(true);
            addView(title, new LayoutParams(0, LayoutParams.WRAP_CONTENT, 1));

            stateDot = dot(c);
            LayoutParams sdlp = new LayoutParams(Ui.dp(c, 7), Ui.dp(c, 7));
            sdlp.leftMargin = Ui.dp(c, 10);
            sdlp.rightMargin = Ui.dp(c, 6);
            addView(stateDot, sdlp);

            state = text(c, 12, 0, "sans-serif");
            state.setTextColor(Ui.onPillDetail());
            state.setDuplicateParentStateEnabled(true);
            addView(state, new LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT));

            setOnFocusChangeListener((v, has) -> {
                v.animate().scaleX(has ? 1.03f : 1f).scaleY(has ? 1.03f : 1f).setDuration(150).start();
                if (has) announce();
            });
            setOnClickListener(v -> {
                if (line != null && line.chat != null && callbacks != null) callbacks.onSelected(line.chat);
            });
        }

        /** A new chat, or one that changed state: fades in, sliding a little from the right. */
        void slideIn() {
            setAlpha(0f);
            setTranslationX(Ui.dp(getContext(), 16));
            animate().alpha(1f).translationX(0).setDuration(350).setInterpolator(new DecelerateInterpolator()).start();
        }

        private View dot(Context c) {
            View v = new View(c);
            GradientDrawable d = new GradientDrawable();
            d.setShape(GradientDrawable.OVAL);
            v.setBackground(d);
            return v;
        }

        void bind(Line l) {
            line = l;
            String brand = l.chat != null ? l.chat.brand : "";
            int logoRes = icon(brand);
            logo.setVisibility(logoRes != 0 ? VISIBLE : GONE);
            if (logoRes != 0) {
                logo.setImageResource(logoRes);
                logo.setImageTintList(tinted(brand) ? Ui.onPill(false) : null);
            }
            // With a logo the state's colour moves to a dot beside the state.
            dot.setVisibility(logoRes != 0 ? GONE : VISIBLE);
            stateDot.setVisibility(logoRes != 0 && !l.status.isEmpty() ? VISIBLE : GONE);
            ((GradientDrawable) dot.getBackground()).setColor(l.color);
            ((GradientDrawable) stateDot.getBackground()).setColor(l.color);
            title.setText(l.title);
            state.setText(l.status);
            state.setVisibility(l.status.isEmpty() ? GONE : VISIBLE);
            boolean focusable = l.chat != null || "pair".equals(l.key);
            setFocusable(focusable);
            setClickable(focusable);
            title.setTextColor(focusable ? Ui.onPill(false) : Ui.onPill(true));
        }

        void announce() {
            if (line != null && callbacks != null) {
                callbacks.onFocused(line.chat != null ? line.chat.title : line.title, line.hint,
                        line.chat != null ? color(line.chat.state) : Ui.SLATE);
            }
        }
    }
}
