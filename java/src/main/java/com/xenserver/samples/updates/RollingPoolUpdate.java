package com.xenserver.samples.updates;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Repository;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.enableWhenBooted;
import static com.xenserver.samples.Helpers.introduceUpdateRepositories;
import static com.xenserver.samples.Helpers.waitForRestart;
import static com.xenserver.samples.PoolConnection.connect;

public final class RollingPoolUpdate {
    private RollingPoolUpdate() {
    }

    /**
     * Rolling pool update.
     *
     * <p>Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host
     * in turn disable it, evacuate its VMs to the rest of the pool, apply the updates, reboot, and
     * re-enable it — host-by-host orchestration.
     *
     * <p>Needs an enabled update repository the same way apply-update does - introduce and attach a
     * throwaway one, forget it again afterwards. Modern xapi (&gt;=23.18.0) doesn't reboot a host for you:
     * it only records pending guidance, so only reboot (or restart the toolstack) when the applied batch
     * actually asks for it.
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
        Set<Repository> repos = introduceUpdateRepositories(conn, repoUrl, sourceUrl);
        // Remember the pool's own repositories, to put them back afterwards.
        Set<Repository> previous = pool.getRepositories(conn);
        pool.setRepositories(conn, repos);
        try {
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());

            // The rolling pattern behind XenCenter's automated Install Updates:
            // disable -> evacuate -> apply -> reboot (only if asked) -> re-enable, one host at a time.
            for (Map.Entry<Host, Host.Record> e : Host.getAllRecords(conn).entrySet()) {
                Host host = e.getKey();
                System.out.println("Updating " + e.getValue().nameLabel + ":");
                host.disable(conn);            // stop new VMs landing here
                host.evacuate(conn);           // move running guests to the rest of the pool
                host.applyUpdates(conn, hash); // apply the synced updates
                Set<Types.UpdateGuidances> guidance = host.getPendingGuidances(conn);
                System.out.println("  applied; pending guidance = " + guidance);
                if (guidance.contains(Types.UpdateGuidances.REBOOT_HOST)
                        || guidance.contains(Types.UpdateGuidances.RESTART_TOOLSTACK)) {
                    // Either restart returns before it has happened, and if this host is the coordinator
                    // it takes this connection with it - so note when the host last started, restart it,
                    // and reconnect until it reports a newer start and is live again.
                    boolean reboot = guidance.contains(Types.UpdateGuidances.REBOOT_HOST);
                    String key = reboot ? "boot_time" : "agent_start_time";
                    String before = host.getOtherConfig(conn).get(key);
                    if (reboot) {
                        host.reboot(conn);     // reboot into the updated software
                    } else {
                        host.restartAgent(conn);
                    }
                    conn = waitForRestart(url, user, password, e.getValue().uuid, key, before);
                }
                enableWhenBooted(conn, host);  // return the host to service
            }
        } finally {
            pool.setRepositories(conn, previous);
            for (Repository repo : repos) repo.forget(conn);
        }
        System.out.println("OK: rolling-pool-update");
        Session.logout(conn);
    }
}
