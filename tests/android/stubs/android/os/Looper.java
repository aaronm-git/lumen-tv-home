package android.os;

import java.util.ArrayList;
import java.util.List;

/** Test stand-in: a queue of runnables run in time order on one thread. */
public final class Looper {
    private static Looper main;

    static final class Message {
        final Handler h;
        final Runnable r;
        final long when, seq;

        Message(Handler h, Runnable r, long when, long seq) {
            this.h = h;
            this.r = r;
            this.when = when;
            this.seq = seq;
        }
    }

    private final List<Message> queue = new ArrayList<>();
    private long seq;
    private boolean quitting;

    public static synchronized Looper getMainLooper() {
        if (main == null) {
            HandlerThread t = new HandlerThread("main");
            t.setDaemon(true);
            t.start();
            main = t.getLooper();
        }
        return main;
    }

    synchronized void enqueue(Handler h, Runnable r, long delay) {
        queue.add(new Message(h, r, SystemClock.uptimeMillis() + delay, seq++));
        notifyAll();
    }

    synchronized void remove(Handler h) {
        queue.removeIf(m -> m.h == h);
    }

    synchronized void quit() {
        quitting = true;
        notifyAll();
    }

    void loop() {
        while (true) {
            Message next;
            synchronized (this) {
                while (true) {
                    next = null;
                    for (Message m : queue) {
                        if (next == null || m.when < next.when || (m.when == next.when && m.seq < next.seq)) next = m;
                    }
                    long now = SystemClock.uptimeMillis();
                    if (next != null && next.when <= now) break;
                    if (quitting && (next == null || next.when > now)) return;
                    try {
                        wait(next == null ? 0 : Math.max(1, next.when - now));
                    } catch (InterruptedException e) {
                        return;
                    }
                }
                queue.remove(next);
            }
            next.r.run();
        }
    }
}
