package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import java.util.Arrays;
import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureNrpe {
    private ConfigureNrpe() {
    }

    /**
     * Configure NRPE monitoring.
     *
     * <p>Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read
     * its status and configuration, enable it and permit a monitoring host, then read it back.
     *
     * <p>host.callPlugin is per-host - there is no pool-wide fan-out for plugin calls the way there is for
     * pool.enableSsh - so configure every host in the pool, and restore each one to exactly the state
     * (enabled or not, and its configuration) it was found in afterwards.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureNrpe.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            for (Host host : Host.getAll(conn)) {
                String label = host.getNameLabel(conn);

                // Capture what we're about to change, to put back afterwards.
                String statusBefore = host.callPlugin(conn, "nrpe", "status", new java.util.HashMap<>()).trim();
                String[] statusWords = statusBefore.split("\\s+");
                boolean wasEnabled = statusWords[statusWords.length - 1].equals("enabled");
                Map<String, String> beforeConfig = new java.util.HashMap<>();
                for (String line : host.callPlugin(conn, "nrpe", "get-config", new java.util.HashMap<>()).split("\n")) {
                    String[] parts = line.split(":", 2);
                    if (parts.length == 2
                            && Arrays.asList("allowed_hosts", "debug", "ssl_logging").contains(parts[0].trim()))
                        beforeConfig.put(parts[0].trim(), parts[1].trim());
                }

                System.out.println(label + ": NRPE status before: " + statusBefore);
                host.callPlugin(conn, "nrpe", "enable", new java.util.HashMap<>());
                Map<String, String> cfg = new java.util.HashMap<>();
                cfg.put("allowed_hosts", "127.0.0.1,::1,192.0.2.60");
                cfg.put("debug", "0");
                cfg.put("ssl_logging", "0x00");
                host.callPlugin(conn, "nrpe", "set-config", cfg);
                host.callPlugin(conn, "nrpe", "restart", new java.util.HashMap<>());
                System.out.println("  status after:  "
                        + host.callPlugin(conn, "nrpe", "status", new java.util.HashMap<>()).trim());
                for (String line : host.callPlugin(conn, "nrpe", "get-config", new java.util.HashMap<>()).split("\n")) {
                    if (line.startsWith("allowed_hosts:"))
                        System.out.println("  allowed hosts: " + line.split(":", 2)[1].trim());
                }

                // Restore exactly what was found, rather than always disabling: a host that already had
                // NRPE enabled and configured should not be left changed.
                host.callPlugin(conn, "nrpe", "set-config", beforeConfig);
                if (wasEnabled)
                    host.callPlugin(conn, "nrpe", "restart", new java.util.HashMap<>());
                else
                    host.callPlugin(conn, "nrpe", "disable", new java.util.HashMap<>());
            }
            System.out.println("OK: configure-nrpe");
        } finally {
            Session.logout(conn);
        }
    }
}
