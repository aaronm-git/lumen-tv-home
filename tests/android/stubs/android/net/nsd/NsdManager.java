package android.net.nsd;

public class NsdManager {
    public static final int PROTOCOL_DNS_SD = 1;

    public interface DiscoveryListener {
        void onServiceFound(NsdServiceInfo info);

        void onStartDiscoveryFailed(String type, int error);

        void onDiscoveryStarted(String type);

        void onDiscoveryStopped(String type);

        void onServiceLost(NsdServiceInfo info);

        void onStopDiscoveryFailed(String type, int error);
    }

    public interface ResolveListener {
        void onServiceResolved(NsdServiceInfo info);

        void onResolveFailed(NsdServiceInfo info, int error);
    }

    public void discoverServices(String type, int protocol, DiscoveryListener l) {}

    public void stopServiceDiscovery(DiscoveryListener l) {}

    public void resolveService(NsdServiceInfo info, ResolveListener l) {}
}
