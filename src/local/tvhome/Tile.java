package local.tvhome;

import android.animation.ObjectAnimator;
import android.content.Context;
import android.graphics.Outline;
import android.graphics.Rect;
import android.graphics.drawable.GradientDrawable;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.view.animation.DecelerateInterpolator;
import android.widget.FrameLayout;

class Tile extends FrameLayout {
    private static final DecelerateInterpolator EASE = new DecelerateInterpolator(2f);

    final int accent;
    private final GradientDrawable ring = new GradientDrawable();

    Tile(Context c, int accent) {
        super(c);
        this.accent = accent;
        float radius = Ui.dp(c, 10);
        setFocusable(true);
        setClickable(true);
        setDefaultFocusHighlightEnabled(false);
        setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View v, Outline o) {
                o.setRoundRect(0, 0, v.getWidth(), v.getHeight(), radius);
            }
        });
        setClipToOutline(true);
        setElevation(Ui.dp(c, 2));
        setOutlineSpotShadowColor(accent);
        setOutlineAmbientShadowColor(accent);

        ring.setCornerRadius(radius);
        ring.setStroke(Ui.dp(c, 2), 0xFFFFFFFF);
        ring.setColor(0);
        ring.setAlpha(0);
        setForeground(ring);
    }

    @Override
    protected void onFocusChanged(boolean focused, int direction, Rect previous) {
        super.onFocusChanged(focused, direction, previous);
        float scale = focused ? 1.1f : 1f;
        animate().scaleX(scale).scaleY(scale)
                .translationZ(focused ? Ui.dp(getContext(), 18) : 0)
                .setDuration(180).setInterpolator(EASE).start();
        ObjectAnimator.ofInt(ring, "alpha", ring.getAlpha(), focused ? 235 : 0).setDuration(180).start();
    }
}
