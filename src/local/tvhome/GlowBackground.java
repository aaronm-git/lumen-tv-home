package local.tvhome;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.view.View;

/** Near-black backdrop lit by a soft glow that fades to the focused app's colour. */
final class GlowBackground extends View {
    private static final int BASE = 0xFF07080B;

    private final Paint glow = new Paint(Paint.DITHER_FLAG);
    private final Paint echo = new Paint(Paint.DITHER_FLAG);
    private final Paint shade = new Paint(Paint.DITHER_FLAG);
    private int accent = Ui.SLATE;
    private int target = Ui.SLATE;
    private ValueAnimator anim;

    GlowBackground(Context c) {
        super(c);
    }

    void setAccent(int color) {
        if (color == target) return;
        target = color;
        if (anim != null) anim.cancel();
        anim = ValueAnimator.ofArgb(accent, color);
        anim.setDuration(600);
        anim.addUpdateListener(a -> {
            accent = (int) a.getAnimatedValue();
            updateShaders();
            invalidate();
        });
        anim.start();
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        updateShaders();
    }

    private void updateShaders() {
        int w = getWidth(), h = getHeight();
        if (w == 0 || h == 0) return;
        glow.setShader(new RadialGradient(w * 0.85f, -h * 0.1f, w * 0.8f,
                new int[]{Ui.alpha(accent, 0.55f), Ui.alpha(accent, 0.16f), 0},
                new float[]{0f, 0.5f, 1f}, Shader.TileMode.CLAMP));
        echo.setShader(new RadialGradient(w * 0.08f, h * 1.1f, w * 0.55f,
                Ui.alpha(accent, 0.2f), 0, Shader.TileMode.CLAMP));
        shade.setShader(new LinearGradient(0, h * 0.45f, 0, h, 0, 0x8C000000, Shader.TileMode.CLAMP));
    }

    @Override
    protected void onDraw(Canvas canvas) {
        canvas.drawColor(BASE);
        canvas.drawPaint(glow);
        canvas.drawPaint(echo);
        canvas.drawPaint(shade);
    }
}
