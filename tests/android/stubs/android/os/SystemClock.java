package android.os;

/** Test stand-in. */
public final class SystemClock {
    public static long uptimeMillis() {
        return System.nanoTime() / 1_000_000;
    }

    public static long elapsedRealtime() {
        return uptimeMillis();
    }
}
