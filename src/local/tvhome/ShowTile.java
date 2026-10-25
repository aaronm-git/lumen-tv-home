package local.tvhome;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

final class ShowTile extends Tile {
    final WatchHistory.Show show;
    final AppEntry app;

    ShowTile(Context c, WatchHistory.Show show, Bitmap art, int accent, AppEntry app, int w, int h) {
        super(c, accent);
        this.show = show;
        this.app = app;

        ImageView image = new ImageView(c);
        image.setScaleType(ImageView.ScaleType.CENTER_CROP);
        if (art != null) image.setImageBitmap(art);
        else if (app.banner != null) image.setImageDrawable(app.banner);
        else image.setBackgroundColor(Ui.mix(accent, 0xFF000000, 0.6f));
        addView(image, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));

        View shade = new View(c);
        shade.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP,
                new int[]{0xE6000000, 0x99000000, 0x00000000}));
        addView(shade, new LayoutParams(LayoutParams.MATCH_PARENT, Math.round(h * 0.7f), Gravity.BOTTOM));

        int pad = Ui.dp(c, 10);
        LinearLayout texts = new LinearLayout(c);
        texts.setOrientation(LinearLayout.VERTICAL);
        texts.setPadding(pad, 0, pad, Ui.dp(c, 12));
        texts.addView(label(c, show.title, 13, 0xFFFFFFFF, "sans-serif-medium"));
        if (show.subtitle != null) texts.addView(label(c, show.subtitle, 11, 0xB3FFFFFF, "sans-serif"));
        addView(texts, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM));

        ImageView badge = new ImageView(c);
        badge.setImageDrawable(app.icon);
        badge.setScaleType(ImageView.ScaleType.CENTER_CROP);
        float r = Ui.dp(c, 5);
        badge.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View v, Outline o) {
                o.setRoundRect(0, 0, v.getWidth(), v.getHeight(), r);
            }
        });
        badge.setClipToOutline(true);
        int size = Ui.dp(c, 22);
        LayoutParams badgeLp = new LayoutParams(size, size, Gravity.TOP | Gravity.START);
        badgeLp.leftMargin = Ui.dp(c, 8);
        badgeLp.topMargin = Ui.dp(c, 8);
        addView(badge, badgeLp);

        float progress = show.progress();
        if (progress >= 0) {
            LayoutParams barLp = new LayoutParams(LayoutParams.MATCH_PARENT, Ui.dp(c, 3), Gravity.BOTTOM);
            barLp.leftMargin = pad;
            barLp.rightMargin = pad;
            barLp.bottomMargin = Ui.dp(c, 6);
            addView(new ProgressBar(c, progress), barLp);
        }
    }

    private static TextView label(Context c, String text, float sp, int color, String family) {
        TextView t = new TextView(c);
        t.setText(text);
        t.setTextSize(sp);
        t.setTextColor(color);
        t.setTypeface(Typeface.create(family, Typeface.NORMAL));
        t.setSingleLine();
        t.setEllipsize(TextUtils.TruncateAt.END);
        return t;
    }

    private static final class ProgressBar extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final float progress;

        ProgressBar(Context c, float progress) {
            super(c);
            this.progress = progress;
        }

        @Override
        protected void onDraw(Canvas canvas) {
            float h = getHeight(), r = h / 2;
            paint.setColor(0x4DFFFFFF);
            canvas.drawRoundRect(0, 0, getWidth(), h, r, r, paint);
            paint.setColor(0xFFFFFFFF);
            canvas.drawRoundRect(0, 0, Math.max(h, getWidth() * progress), h, r, r, paint);
        }
    }
}
