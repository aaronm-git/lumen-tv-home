package android.content;

/** Test stand-in: one in-memory preferences file, and no system services. */
public class Context {
    public static final int MODE_PRIVATE = 0;
    public static final String NSD_SERVICE = "servicediscovery";
    public final SharedPreferences prefs = new SharedPreferences();

    public Context getApplicationContext() {
        return this;
    }

    public SharedPreferences getSharedPreferences(String name, int mode) {
        return prefs;
    }

    public Object getSystemService(String name) {
        return null;
    }
}
