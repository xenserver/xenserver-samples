package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureConsoleAccess {
    private ConfigureConsoleAccess() {
    }

    /**
     * Configure console access.
     *
     * <p>Tighten how consoles and management traffic may be used: idle timeouts for the pool's own
     * consoles and for VM consoles, one session at a time, and refusing plain HTTP. Restore every
     * value it changed afterwards.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureConsoleAccess.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Idle console sessions are set at two levels - the pool's own management consoles and the
            // VM consoles it serves - and a host can override the pool's. Requiring HTTPS refuses plain
            // HTTP to the management interface altogether.
            Pool pool = Pool.getAll(conn).iterator().next();
            Host host = pool.getMaster(conn);

            // NB: pool.https_only and pool.console_idle_timeout are SET below but never read back AT THE
            // POOL LEVEL. SDK 26.14 generates a setter and no getter for either there, because both are
            // really fan-outs that call the equivalent Host.set* on every host rather than pool fields of
            // their own. host.https_only and host.console_idle_timeout ARE ordinary readable fields, so
            // read this host's values back through them instead, to show the effect and to know what to
            // restore.
            long beforeVmConsoleIdleTimeout = pool.getVmConsoleIdleTimeout(conn);
            boolean beforeLimitConsoleSessions = pool.getLimitConsoleSessions(conn);
            long beforeHostConsoleIdleTimeout = host.getConsoleIdleTimeout(conn);
            boolean beforeHostHttpsOnly = host.getHttpsOnly(conn);
            System.out.printf("  %-26s %ss%n", "VM console idle timeout", beforeVmConsoleIdleTimeout);
            System.out.printf("  %-26s %s%n", "limit console sessions", beforeLimitConsoleSessions);
            System.out.printf("  %-26s %ss%n", "host console idle timeout", beforeHostConsoleIdleTimeout);
            System.out.printf("  %-26s %s%n", "host https only", beforeHostHttpsOnly);

            // Ten minutes of inactivity, one console session at a time, and no plain HTTP.
            pool.setConsoleIdleTimeout(conn, 600L);
            pool.setVmConsoleIdleTimeout(conn, 600L);
            pool.setLimitConsoleSessions(conn, true);
            host.setConsoleIdleTimeout(conn, 300L);
            pool.setHttpsOnly(conn, true);

            System.out.println("after tightening:");
            System.out.printf("  %-26s %ss%n", "VM console idle timeout", pool.getVmConsoleIdleTimeout(conn));
            System.out.printf("  %-26s %s%n", "limit console sessions", pool.getLimitConsoleSessions(conn));
            System.out.printf("  %-26s %ss%n", "host console idle timeout", host.getConsoleIdleTimeout(conn));
            System.out.printf("  %-26s %s%n", "host https only", host.getHttpsOnly(conn));

            pool.setHttpsOnly(conn, beforeHostHttpsOnly);
            pool.setConsoleIdleTimeout(conn, beforeHostConsoleIdleTimeout);
            pool.setVmConsoleIdleTimeout(conn, beforeVmConsoleIdleTimeout);
            pool.setLimitConsoleSessions(conn, beforeLimitConsoleSessions);
            host.setConsoleIdleTimeout(conn, beforeHostConsoleIdleTimeout);
            System.out.println("  restored");
            System.out.println("OK: configure-console-access");
        } finally {
            Session.logout(conn);
        }
    }
}
