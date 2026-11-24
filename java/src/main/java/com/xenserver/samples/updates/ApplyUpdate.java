package com.xenserver.samples.updates;

import com.xenserver.samples.Helpers.AttachedRepository;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import java.util.Set;

import static com.xenserver.samples.Helpers.applyUpdatesToHost;
import static com.xenserver.samples.Helpers.attachUpdateRepository;
import static com.xenserver.samples.Helpers.checkNoPendingGuidance;
import static com.xenserver.samples.Helpers.detachUpdateRepository;
import static com.xenserver.samples.Helpers.reportVmGuidance;
import static com.xenserver.samples.PoolConnection.connect;

public final class ApplyUpdate {
    private ApplyUpdate() {
    }

    /**
     * Apply updates from the CDN.
     *
     * <p>Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator,
     * unless you name another - then act on that host's post-update guidance.
     *
     * <p>The documentation asks for the coordinator to be updated before any other host, so update it
     * first, then run this again naming each of the others - or use RollingPoolUpdate to do the whole pool
     * in one go. Before changing anything, Helpers.checkNoPendingGuidance stops if a host or VM still has
     * mandatory guidance pending from an earlier update. Helpers.attachUpdateRepository checks that HA and
     * Workload Balancing are off and attaches a throwaway update repository, which pool.syncUpdates needs;
     * it is forgotten again afterwards. Helpers.applyUpdatesToHost does the rest: evacuating the host first
     * if that turns out to be needed, acting on its post-update guidance, and returning it to service.
     * Finally report the guidance left for VMs, such as restarting one to pick the update up - that is the
     * VM owner's call.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ApplyUpdate.run("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
     * "https://repo-src.ops.xenserver.com/xs9", "");
     * }</pre>
     */
    public static void run(String url, String user, String password, String repoUrl,
            String sourceUrl, String hostName) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        Host host;
        if (!hostName.isEmpty()) {
            Set<Host> hosts = Host.getByNameLabel(conn, hostName);
            if (hosts.size() != 1) {
                throw new IllegalStateException("expected one host named '" + hostName + "', found "
                        + hosts.size());
            }
            host = hosts.iterator().next();
        } else {
            host = pool.getMaster(conn);
        }
        String name = host.getNameLabel(conn);
        checkNoPendingGuidance(conn);

        AttachedRepository attached = attachUpdateRepository(conn, pool, repoUrl, sourceUrl);
        try {
            // Sync the pool's update metadata; the returned hash identifies the synced set.
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());
            conn = applyUpdatesToHost(conn, url, user, password, host, hash, name + ": ");
        } finally {
            detachUpdateRepository(conn, pool, attached);
        }
        reportVmGuidance(conn);
        System.out.println("OK: apply-update");
        Session.logout(conn);
    }
}
