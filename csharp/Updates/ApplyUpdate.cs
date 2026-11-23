using System;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator, unless
    /// you name another - then act on that host's post-update guidance.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ApplyUpdate("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    ///     "https://repo-src.ops.xenserver.com/xs9");
    /// </code>
    /// </example>
    public static void ApplyUpdate(string url, string user, string password, string repoUrl, string sourceUrl,
        string hostName = "")
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session)[0];
        // The documentation asks for the coordinator to be updated before any other host, so update it
        // first, then run this again naming each of the others - or use rolling-pool-update to do the
        // whole pool in one go.
        XenRef<Host> hostRef;
        if (hostName != "")
        {
            var hosts = Host.get_by_name_label(session, hostName);
            if (hosts.Count != 1)
                throw new InvalidOperationException($"expected one host named '{hostName}', found {hosts.Count}");
            hostRef = hosts[0];
        }
        else
        {
            hostRef = Pool.get_master(session, pool);
        }
        var name = Host.get_name_label(session, hostRef);

        // AttachUpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
        // update repository, which Pool.sync_updates needs; it is forgotten again afterwards.
        var (repo, previous) = AttachUpdateRepository(session, pool, repoUrl, sourceUrl);
        try
        {
            // Sync the pool's update metadata; the returned hash identifies the synced set.
            var hash = Pool.sync_updates(session, pool, false, "", "");
            Console.WriteLine($"Synced updates; hash length {hash.Length}");
            // ApplyUpdatesToHost does the rest: evacuating the host first if that turns out to be needed,
            // acting on its post-update guidance, and returning it to service.
            session = ApplyUpdatesToHost(session, url, user, password, hostRef, hash, $"{name}: ");
        }
        finally
        {
            DetachUpdateRepository(session, pool, repo, previous);
        }
        Console.WriteLine("OK: apply-update");
        session.logout();
    }
}
