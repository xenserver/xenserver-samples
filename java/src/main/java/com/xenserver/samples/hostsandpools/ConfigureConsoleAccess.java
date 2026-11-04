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
     * consoles and for VM consoles, one session at a time, and refusing plain HTTP.
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

            // NB: pool.https_only and pool.console_idle_timeout are SET below but never read back. SDK
            // 26.14 generates a setter and no getter for both (unlike host.console_idle_timeout, which
            // has both), so they cannot be read through the typed bindings at all - and a sample that
            // reached past its own binding to show a value would be teaching a workaround rather than
            // the API.
            System.out.printf("  %-26s %ss%n", "VM console idle timeout", pool.getVmConsoleIdleTimeout(conn));
            System.out.printf("  %-26s %s%n", "limit console sessions", pool.getLimitConsoleSessions(conn));
            System.out.printf("  %-26s %ss%n", "host console idle timeout", host.getConsoleIdleTimeout(conn));

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

            pool.setHttpsOnly(conn, false);
            pool.setConsoleIdleTimeout(conn, 0L);
            pool.setVmConsoleIdleTimeout(conn, 0L);
            pool.setLimitConsoleSessions(conn, false);
            host.setConsoleIdleTimeout(conn, 0L);
            System.out.println("  restored");
            System.out.println("OK: configure-console-access");
        } finally {
            Session.logout(conn);
        }
    }
}
