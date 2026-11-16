package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import java.util.HashMap;
import java.util.Map;
import java.util.TreeMap;

import static com.xenserver.samples.PoolConnection.connect;

public final class HostPowerOn {
    private HostPowerOn() {
    }

    /**
     * Configure host power on.
     *
     * <p>Set a host's out-of-band power-on mode and credentials, then read them back.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Host host = Host.getAll(conn).iterator().next();

        // Save the original mode and config so the example restores the host to how it found it, not
        // to a blank "no power-on configured" state.
        String originalMode = host.getPowerOnMode(conn);
        Map<String, String> originalConfig = host.getPowerOnConfig(conn);

        // Mode and config travel together: the config carries the credentials the mode needs.
        // "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
        // modes were removed from the real power-on plugin and fail the moment host.power_on is actually
        // called.
        Map<String, String> cfg = new HashMap<>();
        host.setPowerOnMode(conn, "wake-on-lan", cfg);
        System.out.println("Power-on mode:  " + host.getPowerOnMode(conn));
        Map<String, String> config = host.getPowerOnConfig(conn);
        if (!config.isEmpty()) {
            for (Map.Entry<String, String> e : new TreeMap<>(config).entrySet()) {
                System.out.println("  " + e.getKey() + " = " + e.getValue());
            }
        } else {
            System.out.println("  no credentials needed");
        }

        host.setPowerOnMode(conn, originalMode, originalConfig);
        String restored = host.getPowerOnMode(conn);
        System.out.println("Restored power-on mode: " + (restored.isEmpty() ? "(none)" : restored));
        System.out.println("OK: host-power-on");
        Session.logout(conn);
    }
}
