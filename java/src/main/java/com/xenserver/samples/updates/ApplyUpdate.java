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

public final class ApplyUpdate {
    private ApplyUpdate() {
    }

    /**
     * Apply updates from the CDN.
     *
     * <p>Sync the pool's update metadata from the CDN and apply it to every host, starting with the pool
     * coordinator, then read each host's post-update reboot guidance.
     *
     * <p>Host.applyUpdates refuses with HOST_EVACUATION_IS_REQUIRED (handled below) or HA_IS_ENABLED
     * while HA is on, and the documentation also asks for Workload Balancing to be switched off before
     * you start updating - so check both up front and stop rather than disabling either for you; turn
     * them back on again once the update is done.
     *
     * <p>pool.syncUpdates needs at least one repository with update=True enabled (NO_REPOSITORY_ENABLED
     * otherwise) - introduce and attach a throwaway one, and forget it again afterwards. Applying a batch
     * whose mandatory guidance needs an evacuation fails with HOST_EVACUATION_IS_REQUIRED unless the
     * host's resident VMs are moved off first; handle that rather than assuming an update batch never asks
     * for one. Only call host.reboot/host.restart_agent when the RETURNED pending guidance actually
     * contains REBOOT_HOST/RESTART_TOOLSTACK (modern xapi, &gt;=23.18.0, never auto-reboots - it only
     * records guidance) - not unconditionally after every apply. Guidance that targets VMs instead of
     * hosts (for example restarting a VM) is not handled here.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ApplyUpdate.run("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
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
            // Sync the pool's update metadata; the returned hash identifies the synced set.
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());

            // Apply the synced updates to each host, coordinator first as the documentation requires.
            // Then read the reboot guidance to decide whether a host needs a reboot.
            Map<Host, Host.Record> hosts = Host.getAllRecords(conn);
            Host master = pool.getMaster(conn);
            List<Host> ordered = new ArrayList<>();
            ordered.add(master);
            for (Host h : hosts.keySet()) {
                if (!h.equals(master)) ordered.add(h);
            }
            for (Host host : ordered) {
                Host.Record rec = hosts.get(host);
                try {
                    host.applyUpdates(conn, hash);
                } catch (Types.HostEvacuationIsRequired ex) {
                    System.out.println("  " + rec.nameLabel + ": needs evacuating first; "
                            + "evacuating and retrying");
                    host.disable(conn);
                    host.evacuate(conn);
                    host.applyUpdates(conn, hash);
                    host.enable(conn);
                }
                Set<Types.UpdateGuidances> guidance = host.getPendingGuidances(conn);
                System.out.println("  " + rec.nameLabel + ": applied; pending guidance = " + guidance);
                boolean rebooting = guidance.contains(Types.UpdateGuidances.REBOOT_HOST);
                if (rebooting || guidance.contains(Types.UpdateGuidances.RESTART_TOOLSTACK)) {
                    // As in rolling-pool-update: either restart returns before it has happened, and the
                    // coordinator's takes this connection's session with it - so wait for it, reconnecting.
                    String key = rebooting ? "boot_time" : "agent_start_time";
                    String before = host.getOtherConfig(conn).get(key);
                    if (rebooting) host.reboot(conn);
                    else host.restartAgent(conn);
                    conn = waitForRestart(url, user, password, rec.uuid, key, before);
                }
                // apply_updates disables the host while it works (auto_enable: a restart puts it back) -
                // with no restart to do, nothing re-enables it. Return it to service either way.
                enableWhenBooted(conn, host);
            }
        } finally {
            pool.setRepositories(conn, previous);
            for (Repository repo : repos) repo.forget(conn);
        }
        System.out.println("OK: apply-update");
        Session.logout(conn);
    }
}
