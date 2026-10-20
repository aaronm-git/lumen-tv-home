package android.os;

/** Test stand-in. */
public class Handler {
    private final Looper looper;

    public Handler(Looper looper) {
        this.looper = looper;
    }

    public final boolean post(Runnable r) {
        looper.enqueue(this, r, 0);
        return true;
    }

    public final boolean postDelayed(Runnable r, long delay) {
        looper.enqueue(this, r, delay);
        return true;
    }

    public final void removeCallbacksAndMessages(Object token) {
        looper.remove(this);
    }
}
