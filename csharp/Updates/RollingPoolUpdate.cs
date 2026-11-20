using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
    /// coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
    /// update asks for that, and return it to service.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.RollingPoolUpdate("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    ///     "https://repo-src.ops.xenserver.com/xs9");
    /// </code>
    /// </example>
    public static void RollingPoolUpdate(string url, string user, string password, string repoUrl, string sourceUrl)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session)[0];
        var master = Pool.get_master(session, pool);
        var hosts = new[] { master }.Concat(Host.get_all(session).Where(r => !r.Equals(master))).ToList();
        // Check first that every host can be emptied: get_vms_which_prevent_evacuation names the VMs that
        // could not move anywhere else (for example a VM with a disk on the host's local storage, or a pool
        // with nowhere else to put them) - stop before changing anything if there are any.
        foreach (var hostRef in hosts)
        {
            var blocking = Host.get_vms_which_prevent_evacuation(session, hostRef);
            if (blocking.Count > 0)
                throw new InvalidOperationException(
                    $"{Host.get_name_label(session, hostRef)} cannot be evacuated: move or shut down " +
                    $"{string.Join(", ", blocking.Keys.Select(vm => VM.get_name_label(session, vm)))} first");
        }

        // AttachUpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
        // update repository, which Pool.sync_updates needs; it is forgotten again afterwards.
        var (repo, previous) = AttachUpdateRepository(session, pool, repoUrl, sourceUrl);
        try
        {
            var hash = Pool.sync_updates(session, pool, false, "", "");
            Console.WriteLine($"Synced updates; hash length {hash.Length}");
            // For each host: disable it so nothing new starts there, evacuate it (live-migrating its VMs
            // to the other hosts), and let ApplyUpdatesToHost apply the updates, restart the host or its
            // toolstack if the update asks for that, and enable it again. The VMs stay where evacuation
            // put them.
            foreach (var hostRef in hosts)
            {
                Console.WriteLine($"Updating {Host.get_name_label(session, hostRef)}: moving its VMs to the rest of the pool");
                Host.disable(session, hostRef);
                Host.evacuate(session, hostRef);
                session = ApplyUpdatesToHost(session, url, user, password, hostRef, hash);
            }
        }
        finally
        {
            DetachUpdateRepository(session, pool, repo, previous);
        }
        Console.WriteLine("OK: rolling-pool-update");
        session.logout();
    }
}
