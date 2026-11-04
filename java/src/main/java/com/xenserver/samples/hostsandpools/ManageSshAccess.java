package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageSshAccess {
    private ManageSshAccess() {
    }

    /**
     * Manage SSH access.
     *
     * <p>Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it
     * again — the pool-level call fans out to every host.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageSshAccess.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Pool pool = Pool.getAll(conn).iterator().next();
            // Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
            Map<Host, Host.Record> before = Host.getAllRecords(conn);

            // Timed access is the point: set the timeout first and the server stamps an expiry when SSH
            // is enabled, so a window opened for troubleshooting closes itself. set_ssh_enabled_timeout is
            // itself a pool-wide fan-out call, exactly like enable_ssh/disable_ssh - no need to loop hosts.
            pool.setSshEnabledTimeout(conn, 3600L);

            // The pool call fans out to every host, so there is no need to loop for the enable itself.
            pool.enableSsh(conn);
            for (Host.Record record : Host.getAllRecords(conn).values())
                System.out.printf("%s: ssh enabled=%b, expires %tFT%<tTZ%n",
                    record.nameLabel, record.sshEnabled, record.sshExpiry);

            pool.disableSsh(conn);
            StringBuilder after = new StringBuilder();
            for (Host.Record record : Host.getAllRecords(conn).values()) {
                if (after.length() > 0) after.append(", ");
                after.append(record.nameLabel).append("=").append(record.sshEnabled);
            }
            System.out.println("After disable: " + after);

            for (Map.Entry<Host, Host.Record> e : before.entrySet()) {
                // first: enabling stamps the expiry from it
                e.getKey().setSshEnabledTimeout(conn, e.getValue().sshEnabledTimeout);
                if (e.getValue().sshEnabled) e.getKey().enableSsh(conn);
            }
            System.out.println("OK: manage-ssh-access");
        } finally {
            Session.logout(conn);
        }
    }
}
