using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in
    /// turn disable it, evacuate its VMs to the rest of the pool, apply the updates, reboot, and re-enable it
    /// — host-by-host orchestration.
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
        // Needs an enabled update repository the same way apply-update does - introduce and attach a
        // throwaway one, forget it again afterwards.
        var pool = Pool.get_all(session)[0].opaque_ref;
        var repos = IntroduceUpdateRepositories(session, repoUrl, sourceUrl);
        // Remember the pool's own repositories, to put them back afterwards.
        var previous = Pool.get_repositories(session, pool);
        Pool.set_repositories(session, pool, repos);
        try
        {
            // Sync the pool's update metadata; the returned hash identifies the synced set.
            var hash = Pool.sync_updates(session, pool, false, "", "");
            Console.WriteLine($"Synced updates; hash length {hash.Length}");

            // Apply them host-by-host so the pool never goes fully offline (the rolling pattern behind
            // XenCenter's automated Install Updates): disable → evacuate → apply → reboot (only if asked)
            // → re-enable. Modern xapi (>=23.18.0) doesn't reboot a host for you: it only records
            // pending_guidances, so only reboot (or restart the toolstack) when the applied batch
            // actually asks for it.
            foreach (var (hostRef, host) in Host.get_all_records(session))
            {
                var h = hostRef.opaque_ref;
                Console.WriteLine($"Updating {host.name_label}:");
                Host.disable(session, h);              // stop new VMs landing here
                Host.evacuate(session, h);             // move running guests to the rest of the pool
                Host.apply_updates(session, h, hash);  // apply the synced updates
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
