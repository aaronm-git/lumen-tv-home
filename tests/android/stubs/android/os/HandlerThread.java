package android.os;

/** Test stand-in. */
public class HandlerThread extends Thread {
    private Looper looper;

    public HandlerThread(String name) {
        super(name);
    }

    @Override
    public void run() {
        Looper l = new Looper();
        synchronized (this) {
            looper = l;
            notifyAll();
        }
        l.loop();
    }

    public synchronized Looper getLooper() {
        while (looper == null) {
            try {
                wait();
            } catch (InterruptedException e) {
                return null;
            }
        }
        return looper;
    }

    public boolean quitSafely() {
        getLooper().quit();
        return true;
    }
}
