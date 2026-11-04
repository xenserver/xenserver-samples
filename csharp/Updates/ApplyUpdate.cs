using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Sync the pool's update metadata from the CDN and apply it to every host, then read each host's
    /// post-update reboot guidance.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ApplyUpdate("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    /// Workflows."https://repo-src.ops.xenserver.com/xs9");
    /// </code>
    /// </example>
    public static void ApplyUpdate(string url, string user, string password, string repoUrl, string sourceUrl)
    {
        var session = Connect(url, user, password);
        // pool.sync_updates needs at least one repository with update=true enabled
        // (NO_REPOSITORY_ENABLED otherwise) - introduce and attach a throwaway one, and forget it again
        // afterwards.
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

            // Apply the synced updates to each host. XenCenter then reads the reboot guidance to decide
            // whether a Rolling Pool Upgrade reboot is needed. Applying a batch whose mandatory guidance
            // needs an evacuation fails with HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs
            // are moved off first - handle that rather than assuming an update batch never needs one.
            foreach (var (hostRef, host) in Host.get_all_records(session))
            {
                try
                {
                    Host.apply_updates(session, hostRef.opaque_ref, hash);
                }
                catch (Failure f) when (f.ErrorDescription[0] == "HOST_EVACUATION_IS_REQUIRED")
                {
                    Console.WriteLine($"  {host.name_label}: needs evacuating first; evacuating and retrying");
                    Host.disable(session, hostRef.opaque_ref);
                    Host.evacuate(session, hostRef.opaque_ref);
                    Host.apply_updates(session, hostRef.opaque_ref, hash);
                    Host.enable(session, hostRef.opaque_ref);
                }
                var guidance = Host.get_pending_guidances(session, hostRef.opaque_ref);
                Console.WriteLine($"  {host.name_label}: applied; pending guidance = " +
                                  $"[{string.Join(", ", guidance)}]");
                // Modern xapi (>=23.18.0) doesn't reboot a host for you: it only records pending_guidances,
                // so only reboot (or restart the toolstack) when the applied batch actually asks for it.
                if (guidance.Contains(update_guidances.reboot_host) ||
                    guidance.Contains(update_guidances.restart_toolstack))
                {
                    // As in rolling-pool-update: either restart returns before it has happened, and the
                    // coordinator's takes this session with it - so wait for it, reconnecting.
                    var rebooting = guidance.Contains(update_guidances.reboot_host);
                    var key = rebooting ? "boot_time" : "agent_start_time";
                    Host.get_other_config(session, hostRef.opaque_ref).TryGetValue(key, out var before);
                    if (rebooting) Host.reboot(session, hostRef.opaque_ref);
                    else Host.restart_agent(session, hostRef.opaque_ref);
                    session = WaitForRestart(url, user, password, host.uuid, key, before);
                }
                // apply_updates disables the host while it works (auto_enable: a restart puts it back) -
                // with no restart to do, nothing re-enables it. Return it to service either way.
                EnableWhenBooted(session, hostRef.opaque_ref);
            }
        }
        finally
        {
            Pool.set_repositories(session, pool, previous);
            foreach (var repo in repos) Repository.forget(session, repo.opaque_ref);
        }
        Console.WriteLine("OK: apply-update");
        session.logout();
    }
}
