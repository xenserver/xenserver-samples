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
        var hosts = HostsCoordinatorFirst(session);
        // Check first, before changing anything, that the update can go through: no host or VM may still have
        // mandatory guidance pending from an earlier update, and every host must be able to empty.
        CheckNoPendingGuidance(session);
        CheckHostsCanBeEvacuated(session, hosts);

        // AttachUpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
        // update repository, which Pool.sync_updates needs; it is forgotten again afterwards.
        var (repo, previous) = AttachUpdateRepository(session, pool, repoUrl, sourceUrl);
        try
        {
            var hash = Pool.sync_updates(session, pool, false, "", "");
            Console.WriteLine($"Synced updates; hash length {hash.Length}");
            // UpdateHosts updates each host in turn: disable it, evacuate it, apply the updates, restart it or
            // its toolstack if the update asks for that, and enable it again.
            session = UpdateHosts(session, url, user, password, hosts, hash);
        }
        finally
        {
            DetachUpdateRepository(session, pool, repo, previous);
        }
        // Restarting a VM to pick the update up is its owner's call: report what is left.
        ReportVmGuidance(session);
        Console.WriteLine("OK: rolling-pool-update");
        session.logout();
    }
}
