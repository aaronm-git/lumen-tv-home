package local.tvhome;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.Locale;

/** Artwork, title and app of whatever is playing, plus a play/pause button. */
final class NowPlayingCard extends LinearLayout {
    final LinearLayout body;
    final PlayButton button;
    private final ImageView art;
    private final TextView label, title, subtitle;

    MediaController controller;
    String titleText = "";
    String appName = "";
    int accent = Ui.SLATE;
    boolean playing;
    /** Called when the card or its button gains focus. */
    Runnable onFocused;
    private MediaMetadata shownMetadata;

    NowPlayingCard(Context c) {
        super(c);
        setOrientation(HORIZONTAL);
        setGravity(Gravity.CENTER_VERTICAL);
        setClipChildren(false);

        body = new LinearLayout(c);
        body.setOrientation(HORIZONTAL);
        body.setGravity(Gravity.CENTER_VERTICAL);
        body.setFocusable(true);
        body.setClickable(true);
        body.setDefaultFocusHighlightEnabled(false);
        body.setBackground(Ui.pill(Ui.dp(c, 16)));
        body.setPadding(Ui.dp(c, 8), Ui.dp(c, 8), Ui.dp(c, 16), Ui.dp(c, 8));
        body.setOnFocusChangeListener((v, has) -> {
            v.animate().scaleX(has ? 1.04f : 1f).scaleY(has ? 1.04f : 1f).setDuration(150).start();
            if (has && onFocused != null) onFocused.run();
        });

        art = new ImageView(c);
        art.setScaleType(ImageView.ScaleType.CENTER_CROP);
        float radius = Ui.dp(c, 10);
        art.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View v, Outline o) {
                o.setRoundRect(0, 0, v.getWidth(), v.getHeight(), radius);
            }
        });
        art.setClipToOutline(true);
        body.addView(art, new LayoutParams(Ui.dp(c, 60), Ui.dp(c, 60)));

        LinearLayout texts = new LinearLayout(c);
        texts.setOrientation(VERTICAL);
        texts.setDuplicateParentStateEnabled(true);
        texts.setPadding(Ui.dp(c, 12), 0, 0, 0);
        label = text(c, 11, Ui.onPillDetail(), "sans-serif-medium");
        label.setLetterSpacing(0.12f);
        title = text(c, 16, Ui.onPill(false), "sans-serif-medium");
        subtitle = text(c, 13, Ui.onPillDetail(), "sans-serif");
        texts.addView(label);
        texts.addView(title);
        texts.addView(subtitle);
        body.addView(texts, new LayoutParams(Ui.dp(c, 220), LayoutParams.WRAP_CONTENT));
        addView(body, new LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT));

        button = new PlayButton(c);
        LayoutParams lp = new LayoutParams(Ui.dp(c, 52), Ui.dp(c, 52));
        lp.leftMargin = Ui.dp(c, 12);
        addView(button, lp);
        button.setOnFocusChangeListener((v, has) -> {
            if (has && onFocused != null) onFocused.run();
        });
    }

    void bind(MediaController c, MediaMetadata md, boolean isPlaying) {
        controller = c;
        playing = isPlaying;
        button.setPlaying(isPlaying);
        PackageManager pm = getContext().getPackageManager();
        Drawable icon = null;
        appName = c.getPackageName();
        try {
            ApplicationInfo ai = pm.getApplicationInfo(appName, 0);
            appName = pm.getApplicationLabel(ai).toString();
            icon = pm.getApplicationIcon(ai);
        } catch (PackageManager.NameNotFoundException ignored) {
            // Keep the package name as the label.
        }
        label.setText((isPlaying ? "NOW PLAYING" : "PAUSED") + "  ·  " + appName.toUpperCase(Locale.ROOT));

        if (md == shownMetadata) return;  // Only the play state changed.
        shownMetadata = md;
        titleText = NowPlaying.title(md);
        title.setText(titleText);
        String sub = NowPlaying.subtitle(md);
        subtitle.setText(sub);
        subtitle.setVisibility(sub == null ? GONE : VISIBLE);
        Bitmap bmp = NowPlaying.art(md, 160);
        Drawable artwork = bmp != null ? new BitmapDrawable(getResources(), bmp) : icon;
        art.setImageDrawable(artwork);
        accent = Ui.accent(artwork);
    }

    private static TextView text(Context c, float sp, ColorStateList color, String family) {
        TextView t = new TextView(c);
        t.setTextSize(sp);
        t.setTextColor(color);
        t.setTypeface(Typeface.create(family, Typeface.NORMAL));
        t.setSingleLine();
        t.setEllipsize(TextUtils.TruncateAt.END);
        t.setDuplicateParentStateEnabled(true);
        return t;
    }

    /** A round button that draws ▶ or ❚❚ itself, so it needs no image files. */
    static final class PlayButton extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path triangle = new Path();
        private boolean playing;

        PlayButton(Context c) {
            super(c);
            setFocusable(true);
            setClickable(true);
            setDefaultFocusHighlightEnabled(false);
            setBackground(Ui.pill(Ui.dp(c, 999)));
        }

        void setPlaying(boolean p) {
            playing = p;
            invalidate();
        }

        @Override
        protected void onFocusChanged(boolean focused, int direction, Rect previous) {
            super.onFocusChanged(focused, direction, previous);
            animate().scaleX(focused ? 1.1f : 1f).scaleY(focused ? 1.1f : 1f).setDuration(150).start();
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            paint.setColor(isFocused() ? 0xFF0B0D12 : 0xF2FFFFFF);
            float cx = getWidth() / 2f, cy = getHeight() / 2f, s = getWidth() * 0.16f;
            if (playing) {
                float bar = s * 0.55f, gap = s * 0.45f;
                canvas.drawRoundRect(cx - gap - bar, cy - s, cx - gap, cy + s, 2, 2, paint);
                canvas.drawRoundRect(cx + gap, cy - s, cx + gap + bar, cy + s, 2, 2, paint);
            } else {
                triangle.reset();
                triangle.moveTo(cx - s * 0.7f, cy - s);
                triangle.lineTo(cx + s, cy);
                triangle.lineTo(cx - s * 0.7f, cy + s);
                triangle.close();
                canvas.drawPath(triangle, paint);
            }
        }
    }
}
