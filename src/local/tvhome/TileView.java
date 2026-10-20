package local.tvhome;

import android.content.Context;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

/** An app's banner tile. */
final class TileView extends Tile {
    static final int FAVORITE = 1, APP = 2;

    final AppEntry app;
    /** Which row the tile sits in. */
    final int section;
    private final TextView moveBadge;

    TileView(Context c, AppEntry app, int section, int w, int h) {
        super(c, app.accent);
        this.app = app;
        this.section = section;

        if (app.banner != null) {
            ImageView banner = new ImageView(c);
            banner.setScaleType(ImageView.ScaleType.CENTER_CROP);
            banner.setImageDrawable(app.banner);
            addView(banner, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
        } else {
            // No banner: the app's icon and name on a card tinted with its colour.
            setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{
                    Ui.mix(app.accent, 0xFF000000, 0.55f), Ui.mix(app.accent, 0xFF000000, 0.8f)}));
            LinearLayout col = new LinearLayout(c);
            col.setOrientation(LinearLayout.VERTICAL);
            col.setGravity(Gravity.CENTER);
            ImageView icon = new ImageView(c);
            icon.setImageDrawable(app.icon);
            int size = Math.round(h * 0.42f);
            col.addView(icon, new LinearLayout.LayoutParams(size, size));
            TextView label = new TextView(c);
            label.setText(app.label);
            label.setTextSize(12);
            label.setTextColor(0xF2FFFFFF);
            label.setSingleLine();
            label.setEllipsize(TextUtils.TruncateAt.END);
            label.setMaxWidth(w - Ui.dp(c, 16));
            label.setPadding(0, Ui.dp(c, 4), 0, 0);
            col.addView(label);
            addView(col, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
        }

        moveBadge = new TextView(c);
        moveBadge.setText("‹      ›");
        moveBadge.setTextSize(30);
        moveBadge.setTextColor(0xFFFFFFFF);
        moveBadge.setGravity(Gravity.CENTER);
        moveBadge.setBackgroundColor(0x80000000);
        moveBadge.setVisibility(GONE);
        addView(moveBadge, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
    }

    void setMoving(boolean moving) {
        moveBadge.setVisibility(moving ? VISIBLE : GONE);
    }
}
