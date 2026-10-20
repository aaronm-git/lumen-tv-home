package local.tvhome;

import android.content.Context;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * A small card in the top-right corner, over whatever is playing, when a T3 Code chat finishes, fails or needs
 * you. It can't take focus or touches, so the remote keeps controlling the app underneath.
 */
final class AgentAlert {
    private static final long SHOW_MS = 8000;

    private final Context c;
    private final WindowManager wm;
    private LinearLayout card;
    private final Runnable hide = this::hide;

    /** c must be able to add accessibility overlays (the accessibility service). */
    AgentAlert(Context c) {
        this.c = c;
        wm = (WindowManager) c.getSystemService(Context.WINDOW_SERVICE);
    }

    /** Shows the most urgent chat; more than one is mentioned in the label. */
    void show(AgentStatus.Chat chat, int count, String mac) {
        if (card == null) add();
        LinearLayout body = card;
        ((TextView) body.findViewWithTag("label")).setText(count > 1
                ? "T3 CODE  ·  " + count + " CHATS NEED A LOOK" : "T3 CODE  ·  " + mac.toUpperCase(java.util.Locale.ROOT));
        ((TextView) body.findViewWithTag("title")).setText(chat.title);
        TextView sub = body.findViewWithTag("sub");
        String detail = chat.detail.isEmpty() || chat.detail.equals("Finished") ? AgentsCard.stateName(chat.state)
                : AgentsCard.stateName(chat.state) + "  ·  " + chat.detail;
        sub.setText(chat.project.isEmpty() ? detail : detail + "  ·  " + chat.project);
        sub.setTextColor(AgentsCard.color(chat.state));
        ImageView logo = body.findViewWithTag("logo");
        int res = AgentsCard.icon(chat.brand);
        logo.setVisibility(res != 0 ? View.VISIBLE : View.GONE);
        if (res != 0) {
            logo.setImageResource(res);
            logo.setImageTintList(AgentsCard.tinted(chat.brand)
                    ? android.content.res.ColorStateList.valueOf(0xFFFFFFFF) : null);
        }

        body.removeCallbacks(hide);
        body.animate().cancel();
        body.animate().alpha(1f).translationX(0).setDuration(250).start();
        body.postDelayed(hide, SHOW_MS);
    }

    void hide() {
        if (card == null) return;
        LinearLayout body = card;
        body.removeCallbacks(hide);
        body.animate().alpha(0f).translationX(Ui.dp(c, 40)).setDuration(300).withEndAction(() -> {
            if (card == body) {
                wm.removeView(body);
                card = null;
            }
        }).start();
    }

    private void add() {
        card = new LinearLayout(c);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(Ui.dp(c, 18));
        bg.setColor(0xF2141720);
        bg.setStroke(Ui.dp(c, 1), 0x1FFFFFFF);
        card.setBackground(bg);
        card.setPadding(Ui.dp(c, 16), Ui.dp(c, 12), Ui.dp(c, 18), Ui.dp(c, 12));

        ImageView logo = new ImageView(c);
        logo.setTag("logo");
        LinearLayout.LayoutParams llp = new LinearLayout.LayoutParams(Ui.dp(c, 28), Ui.dp(c, 28));
        llp.rightMargin = Ui.dp(c, 14);
        card.addView(logo, llp);

        LinearLayout texts = new LinearLayout(c);
        texts.setOrientation(LinearLayout.VERTICAL);
        texts.addView(text("label", 10, 0x80FFFFFF, "sans-serif-medium"));
        texts.addView(text("title", 16, 0xFFFFFFFF, "sans-serif-medium"));
        texts.addView(text("sub", 13, 0xFFFFFFFF, "sans-serif"));
        card.addView(texts, new LinearLayout.LayoutParams(Ui.dp(c, 300), LinearLayout.LayoutParams.WRAP_CONTENT));

        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        lp.gravity = Gravity.TOP | Gravity.END;
        lp.x = Ui.dp(c, 40);
        lp.y = Ui.dp(c, 32);
        card.setAlpha(0f);
        card.setTranslationX(Ui.dp(c, 40));
        wm.addView(card, lp);
    }

    private TextView text(String tag, float sp, int color, String family) {
        TextView t = new TextView(c);
        t.setTag(tag);
        t.setTextSize(sp);
        t.setTextColor(color);
        t.setTypeface(Typeface.create(family, Typeface.NORMAL));
        t.setSingleLine();
        t.setEllipsize(TextUtils.TruncateAt.END);
        if ("label".equals(tag)) t.setLetterSpacing(0.12f);
        return t;
    }
}
