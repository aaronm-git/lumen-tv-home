package local.tvhome;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;

/** Small drawing helpers shared by the home screen views. */
final class Ui {
    static final int SLATE = 0xFF4A5A7A;
    private static final int[] FOCUSED = {android.R.attr.state_focused};
    private static final int[] DEFAULT = {};

    private Ui() {}

    static int dp(Context c, float dp) {
        return Math.round(dp * c.getResources().getDisplayMetrics().density);
    }

    static int alpha(int color, float a) {
        return (color & 0x00FFFFFF) | (Math.round(a * 255) << 24);
    }

    static int mix(int from, int to, float t) {
        float s = 1 - t;
        return Color.rgb(
                Math.round(Color.red(from) * s + Color.red(to) * t),
                Math.round(Color.green(from) * s + Color.green(to) * t),
                Math.round(Color.blue(from) * s + Color.blue(to) * t));
    }

    /** White when focused, faint glass otherwise. */
    static StateListDrawable pill(float radius) {
        GradientDrawable on = new GradientDrawable();
        on.setCornerRadius(radius);
        on.setColor(0xFFFFFFFF);
        GradientDrawable off = new GradientDrawable();
        off.setCornerRadius(radius);
        off.setColor(0x1AFFFFFF);
        StateListDrawable d = new StateListDrawable();
        d.addState(FOCUSED, on);
        d.addState(DEFAULT, off);
        return d;
    }

    static ColorStateList onPill(boolean dim) {
        return new ColorStateList(new int[][]{FOCUSED, DEFAULT},
                new int[]{0xFF0B0D12, dim ? 0x66FFFFFF : 0xF2FFFFFF});
    }

    static ColorStateList onPillDetail() {
        return new ColorStateList(new int[][]{FOCUSED, DEFAULT}, new int[]{0x990B0D12, 0x80FFFFFF});
    }

    static GradientDrawable card(Context c) {
        GradientDrawable d = new GradientDrawable();
        d.setCornerRadius(dp(c, 20));
        d.setColor(0xF2141720);
        d.setStroke(dp(c, 1), 0x1FFFFFFF);
        return d;
    }

    /** The most vivid colour in a banner or icon, brightened so it glows on black. */
    static int accent(Drawable source) {
        if (source == null) return SLATE;
        Drawable d = source.getConstantState() != null
                ? source.getConstantState().newDrawable().mutate() : source;
        Bitmap bmp = Bitmap.createBitmap(32, 18, Bitmap.Config.ARGB_8888);
        d.setBounds(0, 0, 32, 18);
        d.draw(new Canvas(bmp));

        float[] hsv = new float[3];
        double r = 0, g = 0, b = 0, total = 0;
        for (int y = 0; y < 18; y++) {
            for (int x = 0; x < 32; x++) {
                int p = bmp.getPixel(x, y);
                if (Color.alpha(p) < 128) continue;
                Color.colorToHSV(p, hsv);
                double w = hsv[1] * hsv[1] * hsv[2] + 0.001;
                r += Color.red(p) * w;
                g += Color.green(p) * w;
                b += Color.blue(p) * w;
                total += w;
            }
        }
        bmp.recycle();
        if (total == 0) return SLATE;

        Color.colorToHSV(Color.rgb((int) (r / total), (int) (g / total), (int) (b / total)), hsv);
        if (hsv[1] < 0.18f) return SLATE;
        hsv[1] = Math.min(0.85f, Math.max(0.55f, hsv[1]));
        hsv[2] = 0.9f;
        return Color.HSVToColor(hsv);
    }
}
