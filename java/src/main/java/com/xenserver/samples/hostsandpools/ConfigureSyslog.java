package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureSyslog {
    private ConfigureSyslog() {
    }

    /**
     * Send logs to a remote syslog server.
     *
     * <p>Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the
     * setting is recorded but nothing changes.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureSyslog.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password, String syslogServer)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Two steps, and the second is the one that is easy to miss: setting the destination only
            // records it, and the host keeps logging locally until the syslog daemon is reconfigured to
            // pick the setting up.
            Host host = Pool.getAll(conn).iterator().next().getMaster(conn);

            Map<String, String> logging = host.getLogging(conn);
            System.out.println(host.getNameLabel(conn) + " logging: "
                    + (logging.isEmpty() ? "(local only)" : logging));

            host.removeFromLogging(conn, "syslog_destination");
            host.addToLogging(conn, "syslog_destination", syslogServer);
            host.syslogReconfigure(conn);
            System.out.println("  now logging to: " + host.getLogging(conn).get("syslog_destination"));

            host.removeFromLogging(conn, "syslog_destination");
            host.syslogReconfigure(conn);
            Map<String, String> after = host.getLogging(conn);
            System.out.println("  restored: " + (after.isEmpty() ? "(local only)" : after));
            System.out.println("OK: configure-syslog");
        } finally {
            Session.logout(conn);
        }
    }
}
