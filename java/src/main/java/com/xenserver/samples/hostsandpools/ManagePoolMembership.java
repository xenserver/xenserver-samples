package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import com.xenserver.samples.PoolConnection.CoordinatorUnknown;

import java.util.Map;

import static com.xenserver.samples.Helpers.hostUrl;
import static com.xenserver.samples.PoolConnection.connect;

public final class ManagePoolMembership {
    private ManagePoolMembership() {
    }

    /**
     * Manage pool membership.
     *
     * <p>List the pool's member hosts and which one coordinates it, promote a different host to
     * coordinator, then promote the original back.
     *
     * <p>designateNewMaster runs a two-phase commit across every host and ends by restarting xapi
     * pool-wide (the new coordinator becomes master, every other host becomes its slave) - so the session
     * this call was made on, and the connection itself, do not survive it. Reconnect (with a bounded wait,
     * since xapi is briefly unavailable while it restarts) before touching the pool again, and re-resolve
     * every ref from the fresh session - do not reuse the old session or any ref resolved from it.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        Host original = pool.getMaster(conn);
        String originalName = original.getNameLabel(conn);
        String originalUuid = original.getUuid(conn);
        System.out.println("Coordinator: " + originalName);

        String otherName = null;
        for (Host h : Host.getAll(conn)) {
            System.out.println("  member: " + h.getNameLabel(conn)
                    + (h.equals(original) ? " (coordinator)" : ""));
            if (!h.equals(original)) otherName = h.getNameLabel(conn);
        }
        Host other = hostByName(conn, otherName);
        String otherUuid = other.getUuid(conn);
        // Each new coordinator's own address, to reconnect to if following HOST_IS_SLAVE from the old one
        // fails: Java SDKs up to 26.22 read HostIsSlave.masterIPAddress as "" under JSON-RPC.
        String otherUrl = hostUrl(url, other.getAddress(conn));
        String originalUrl = hostUrl(url, original.getAddress(conn));

        // Promote another member. The pool database moves with the role and clients are redirected, so
        // this briefly interrupts management traffic - it does not move any VM.
        Pool.designateNewMaster(conn, other);
        System.out.println("Promoting:   " + otherName + " (xapi restarts pool-wide; reconnecting)");

        conn = reconnectAfterMasterChange(url, otherUrl, user, password, otherUuid);
        pool = Pool.getAll(conn).iterator().next();
        System.out.println("Promoted:    " + pool.getMaster(conn).getNameLabel(conn));

        // Put it back. Ejecting a member (Pool.eject) is the other half of this surface and is
        // deliberately not shown: it cannot be undone from the pool, because rejoining is initiated
        // by the ejected host.
        Host originalAgain = hostByName(conn, originalName);
        Pool.designateNewMaster(conn, originalAgain);
        System.out.println("Restoring:   " + originalName + " (reconnecting again)");

        conn = reconnectAfterMasterChange(url, originalUrl, user, password, originalUuid);
        pool = Pool.getAll(conn).iterator().next();
        System.out.println("Restored:    " + pool.getMaster(conn).getNameLabel(conn));

        System.out.println("OK: manage-pool-membership");
        Session.logout(conn);
    }

    /**
     * Wait out a pool-wide xapi restart (pool.designateNewMaster) and reconnect.
     *
     * <p>designateNewMaster returns BEFORE the change: for a while the old coordinator still answers, and
     * still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not enough
     * - keep reconnecting until the pool names the new coordinator (by uuid; connect() follows
     * HOST_IS_SLAVE to wherever the coordinator now is). That can take minutes.
     */
    private static Connection reconnectAfterMasterChange(String url, String newMasterUrl, String user,
            String password, String newMasterUuid) throws Exception {
        long deadline = System.currentTimeMillis() + 600_000;
        Object lastError = null;
        while (System.currentTimeMillis() < deadline) {
            try {
                Connection conn;
                try {
                    conn = connect(url, user, password);
                } catch (CoordinatorUnknown e) {
                    conn = connect(newMasterUrl, user, password);
                }
                Host master = Pool.getAll(conn).iterator().next().getMaster(conn);
                // The new coordinator answers before the pool has settled - calls made too soon fail
                // (HANDLE_INVALID on the operation's own task) - so also wait for every host to be back,
                // live and enabled.
                boolean settled = master.getUuid(conn).equals(newMasterUuid);
                if (settled) {
                    for (Map.Entry<Host, Host.Record> e : Host.getAllRecords(conn).entrySet()) {
                        if (!e.getValue().enabled || !e.getValue().metrics.getLive(conn)) {
                            settled = false;
                            break;
                        }
                    }
                }
                if (settled) return conn;
                Session.logout(conn);
                lastError = "the pool has not settled under the new coordinator";
            } catch (Exception e) {
                lastError = e;
            }
            Thread.sleep(5000);
        }
        throw new RuntimeException("the pool did not come back after the master change: " + lastError);
    }

    /**
     * Find a host by its exact name label (used to re-resolve a host across a reconnect).
     */
    private static Host hostByName(Connection conn, String name) throws Exception {
        for (Map.Entry<Host, Host.Record> e : Host.getAllRecords(conn).entrySet())
            if (name.equals(e.getValue().nameLabel)) return e.getKey();
        throw new RuntimeException("no host named '" + name + "' was found");
    }
}
