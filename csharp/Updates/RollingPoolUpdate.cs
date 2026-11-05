using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in
    /// turn - coordinator first - apply the updates (evacuating its VMs first only if that turns out to be
    /// needed), reboot if asked to, and re-enable it — host-by-host orchestration.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.RollingPoolUpdate("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    /// Workflows."https://repo-src.ops.xenserver.com/xs9");
    /// </code>
    /// </example>
    public static void RollingPoolUpdate(string url, string user, string password, string repoUrl, string sourceUrl)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session)[0].opaque_ref;
        // Host.apply_updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks
        // for Workload Balancing to be switched off before you start updating - so check both up front
        // and stop rather than disabling either for you; turn them back on again once the update is done.
        if (Pool.get_ha_enabled(session, pool) || Pool.get_wlb_enabled(session, pool))
            throw new Exception("HA and Workload Balancing must both be off before updating the pool; " +
                                 "disable them, run this again, then re-enable them once it finishes");
        // Needs an enabled update repository the same way apply-update does - introduce and attach a
        // throwaway one, forget it again afterwards.
        var repos = IntroduceUpdateRepositories(session, repoUrl, sourceUrl);
        // Remember the pool's own repositories, to put them back afterwards.
        var previous = Pool.get_repositories(session, pool);
        Pool.set_repositories(session, pool, repos);
        try
        {
            // Sync the pool's update metadata; the returned hash identifies the synced set.
            var hash = Pool.sync_updates(session, pool, false, "", "");
            Console.WriteLine($"Synced updates; hash length {hash.Length}");

            // Apply them host-by-host, coordinator first, so the pool never goes fully offline (the
            // rolling pattern): apply -> evacuate and retry only if that turns out to be needed ->
            // reboot (only if asked) -> re-enable. Modern xapi (>=23.18.0) doesn't reboot a host
            // for you: it only records pending_guidances, so only reboot (or restart the toolstack)
            // when the applied batch actually asks for it. (Guidance that targets VMs instead of
            // hosts, for example restarting a VM, is not handled here.)
            var hosts = Host.get_all_records(session);
            var master = Pool.get_master(session, pool);
            var orderedRefs = new[] { master }.Concat(hosts.Keys.Where(r => r.opaque_ref != master.opaque_ref));
            foreach (var hostRef in orderedRefs)
            {
                var host = hosts[hostRef];
                var h = hostRef.opaque_ref;
                Console.WriteLine($"Updating {host.name_label}:");
                try
                {
                    Host.apply_updates(session, h, hash);  // apply the synced updates
                }
                catch (Failure f) when (f.ErrorDescription[0] == "HOST_EVACUATION_IS_REQUIRED")
                {
                    Console.WriteLine("  needs evacuating first; evacuating and retrying");
                    Host.disable(session, h);   // stop new VMs landing here
                    Host.evacuate(session, h);  // move running guests to the rest of the pool
                    Host.apply_updates(session, h, hash);
                    Host.enable(session, h);
                }
                var guidance = Host.get_pending_guidances(session, h);
                Console.WriteLine($"  applied; pending guidance = [{string.Join(", ", guidance)}]");
                if (guidance.Contains(update_guidances.reboot_host) ||
                    guidance.Contains(update_guidances.restart_toolstack))
                {
                    // Either restart returns before it has happened, and if this host is the coordinator
                    // it takes this session with it - so note when the host last started, restart it, and
                    // reconnect until it reports a newer start and is live again.
                    var rebooting = guidance.Contains(update_guidances.reboot_host);
                    var key = rebooting ? "boot_time" : "agent_start_time";
                    Host.get_other_config(session, h).TryGetValue(key, out var before);
                    if (rebooting) Host.reboot(session, h);           // reboot into the updated software
                    else Host.restart_agent(session, h);
                    session = WaitForRestart(url, user, password, host.uuid, key, before);
                }
                EnableWhenBooted(session, h);          // return the host to service
            }
        }
        finally
        {
            Pool.set_repositories(session, pool, previous);
            foreach (var repo in repos) Repository.forget(session, repo.opaque_ref);
        }
        Console.WriteLine("OK: rolling-pool-update");
        session.logout();
    }
}
