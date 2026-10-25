package android.net.nsd;

import java.net.InetAddress;
import java.util.Map;

public class NsdServiceInfo {
    public Map<String, byte[]> getAttributes() {
        return Map.of();
    }

    public InetAddress getHost() {
        return null;
    }

    public int getPort() {
        return 0;
    }
}
