package com.xenserver.samples.updates;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Repository;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import java.util.ArrayList;
import java.util.List;
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
     * in turn - coordinator first - apply the updates (evacuating its VMs first only if that turns out to
     * be needed), reboot if asked to, and re-enable it — host-by-host orchestration.
     *
     * <p>Host.applyUpdates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
     * Workload Balancing to be switched off before you start updating - so check both up front and stop
     * rather than disabling either for you; turn them back on again once the update is done.
     *
     * <p>Needs an enabled update repository the same way apply-update does - introduce and attach a
     * throwaway one, forget it again afterwards. Modern xapi (&gt;=23.18.0) doesn't reboot a host for you:
     * it only records pending guidance, so only reboot (or restart the toolstack) when the applied batch
     * actually asks for it, and only evacuate a host first if applying without doing so fails with
     * HOST_EVACUATION_IS_REQUIRED - most updates don't need it. Guidance that targets VMs instead of hosts
     * (for example restarting a VM) is not handled here.
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
        if (pool.getHaEnabled(conn) || pool.getWlbEnabled(conn)) {
            throw new RuntimeException("HA and Workload Balancing must both be off before updating the "
                    + "pool; disable them, run this again, then re-enable them once it finishes");
        }
        Set<Repository> repos = introduceUpdateRepositories(conn, repoUrl, sourceUrl);
        // Remember the pool's own repositories, to put them back afterwards.
        Set<Repository> previous = pool.getRepositories(conn);
        pool.setRepositories(conn, repos);
        try {
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());

            // The rolling pattern: apply -> evacuate and retry only if that turns out to be needed ->
            // reboot (only if asked) -> re-enable, one host at a time, coordinator first.
            Map<Host, Host.Record> hosts = Host.getAllRecords(conn);
            Host master = pool.getMaster(conn);
            List<Host> ordered = new ArrayList<>();
            ordered.add(master);
            for (Host h : hosts.keySet()) {
                if (!h.equals(master)) ordered.add(h);
            }
            for (Host host : ordered) {
                Host.Record rec = hosts.get(host);
                System.out.println("Updating " + rec.nameLabel + ":");
                try {
                    host.applyUpdates(conn, hash); // apply the synced updates
                } catch (Types.HostEvacuationIsRequired ex) {
                    System.out.println("  needs evacuating first; evacuating and retrying");
                    host.disable(conn);            // stop new VMs landing here
                    host.evacuate(conn);           // move running guests to the rest of the pool
                    host.applyUpdates(conn, hash);
                    host.enable(conn);
                }
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
                    conn = waitForRestart(url, user, password, rec.uuid, key, before);
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
