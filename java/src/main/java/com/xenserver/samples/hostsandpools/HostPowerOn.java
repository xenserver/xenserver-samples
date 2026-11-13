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

        // Mode and config travel together: the config carries the credentials the mode needs.
        // "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
        // modes were removed from the real power-on plugin and fail the moment host.power_on is actually
        // called.
        Map<String, String> cfg = new HashMap<>();
        host.setPowerOnMode(conn, "wake-on-lan", cfg);
        System.out.println("Power-on mode:  " + host.getPowerOnMode(conn));
        for (Map.Entry<String, String> e : new TreeMap<>(host.getPowerOnConfig(conn)).entrySet()) {
            System.out.println("  " + e.getKey() + " = " + e.getValue());
        }

        host.setPowerOnMode(conn, "", new HashMap<String, String>());
        System.out.println("OK: host-power-on");
        Session.logout(conn);
    }
}
