package com.xenserver.samples.updates;

import com.xenserver.samples.Helpers.AttachedRepository;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import java.util.List;

import static com.xenserver.samples.Helpers.attachUpdateRepository;
import static com.xenserver.samples.Helpers.checkHostsCanBeEvacuated;
import static com.xenserver.samples.Helpers.checkNoPendingGuidance;
import static com.xenserver.samples.Helpers.detachUpdateRepository;
import static com.xenserver.samples.Helpers.hostsCoordinatorFirst;
import static com.xenserver.samples.Helpers.reportVmGuidance;
import static com.xenserver.samples.Helpers.updateHosts;
import static com.xenserver.samples.PoolConnection.connect;

public final class RollingPoolUpdate {
    private RollingPoolUpdate() {
    }

    /**
     * Rolling pool update.
     *
     * <p>Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
     * coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
     * update asks for that, and return it to service.
     *
     * <p>Check first, before changing anything, that the update can go through: no host or VM may still have
     * mandatory guidance pending from an earlier update, and every host must be able to empty
     * (Helpers.checkNoPendingGuidance, Helpers.checkHostsCanBeEvacuated). Then sync, and let
     * Helpers.updateHosts update each host in turn: disable it, evacuate it, apply the updates, restart it or
     * its toolstack if the update asks for that, and enable it again. Finally report the guidance left for
     * VMs, such as restarting one to pick the update up - that is the VM owner's call.
     * Helpers.attachUpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
     * update repository, which pool.syncUpdates needs; it is forgotten again afterwards.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * RollingPoolUpdate.run("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
     * "https://repo-src.ops.xenserver.com/xs9");
     * }</pre>
     */
    public static void run(String url, String user, String password, String repoUrl,
            String sourceUrl) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        List<Host> hosts = hostsCoordinatorFirst(conn);
        checkNoPendingGuidance(conn);
        checkHostsCanBeEvacuated(conn, hosts);

        AttachedRepository attached = attachUpdateRepository(conn, pool, repoUrl, sourceUrl);
        try {
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());
            conn = updateHosts(conn, url, user, password, hosts, hash);
        } finally {
            detachUpdateRepository(conn, pool, attached);
        }
        reportVmGuidance(conn);
        System.out.println("OK: rolling-pool-update");
        Session.logout(conn);
    }
}
