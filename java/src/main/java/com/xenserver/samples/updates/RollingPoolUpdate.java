package com.xenserver.samples.updates;

import com.xenserver.samples.Helpers.AttachedRepository;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.applyUpdatesToHost;
import static com.xenserver.samples.Helpers.attachUpdateRepository;
import static com.xenserver.samples.Helpers.detachUpdateRepository;
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
     * <p>Check first that every host can be emptied: host.getVmsWhichPreventEvacuation names the VMs that
     * could not move anywhere else (for example a VM with a disk on the host's local storage, or a pool with
     * nowhere else to put them) - stop before changing anything if there are any. Then, for each host:
     * disable it so nothing new starts there, evacuate it (live-migrating its VMs to the other hosts), and
     * let Helpers.applyUpdatesToHost apply the updates, restart the host or its toolstack if the update asks
     * for that, and enable it again. The VMs stay where evacuation put them.
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
        Host master = pool.getMaster(conn);
        List<Host> hosts = new ArrayList<>();
        hosts.add(master);
        for (Host h : Host.getAll(conn)) {
            if (!h.equals(master)) hosts.add(h);
        }
        for (Host host : hosts) {
            Map<VM, Set<String>> blocking = host.getVmsWhichPreventEvacuation(conn);
            if (!blocking.isEmpty()) {
                List<String> names = new ArrayList<>();
                for (VM vm : blocking.keySet()) names.add(vm.getNameLabel(conn));
                throw new IllegalStateException(host.getNameLabel(conn) + " cannot be evacuated: move or shut down "
                        + String.join(", ", names) + " first");
            }
        }

        AttachedRepository attached = attachUpdateRepository(conn, pool, repoUrl, sourceUrl);
        try {
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());
            for (Host host : hosts) {
                System.out.println("Updating " + host.getNameLabel(conn) + ": moving its VMs to the rest of the pool");
                host.disable(conn);
                host.evacuate(conn);
                conn = applyUpdatesToHost(conn, url, user, password, host, hash, "");
            }
        } finally {
            detachUpdateRepository(conn, pool, attached);
        }
        System.out.println("OK: rolling-pool-update");
        Session.logout(conn);
    }
}
