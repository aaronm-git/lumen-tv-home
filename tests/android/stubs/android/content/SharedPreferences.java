package android.content;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;

/** Test stand-in (a class here, an interface on Android). beforeApply lets a test pause a write. */
public class SharedPreferences {
    public static volatile Consumer<Map<String, Object>> beforeApply;
    private final Map<String, Object> values = new HashMap<>();

    public synchronized String getString(String k, String fallback) {
        return values.containsKey(k) ? (String) values.get(k) : fallback;
    }

    public synchronized boolean getBoolean(String k, boolean fallback) {
        return values.containsKey(k) ? (Boolean) values.get(k) : fallback;
    }

    public synchronized int getInt(String k, int fallback) {
        return values.containsKey(k) ? (Integer) values.get(k) : fallback;
    }

    public Editor edit() {
        return new Editor();
    }

    public final class Editor {
        private final Map<String, Object> put = new HashMap<>();
        private final Set<String> removed = new HashSet<>();

        public Editor putString(String k, String v) {
            put.put(k, v);
            return this;
        }

        public Editor putBoolean(String k, boolean v) {
            put.put(k, v);
            return this;
        }

        public Editor putInt(String k, int v) {
            put.put(k, v);
            return this;
        }

        public Editor remove(String k) {
            removed.add(k);
            return this;
        }

        public void apply() {
            Consumer<Map<String, Object>> hook = beforeApply;
            if (hook != null) hook.accept(put);
            synchronized (SharedPreferences.this) {
                for (String k : removed) values.remove(k);
                values.putAll(put);
            }
        }
    }
}
