using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it again —
    /// the pool-level call fans out to every host.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ManageSshAccess("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ManageSshAccess(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session)[0];
        // Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
        var before = Host.get_all_records(session)
            .ToDictionary(kv => kv.Key, kv => (kv.Value.ssh_enabled, kv.Value.ssh_enabled_timeout));

        // Timed access is the point: set the timeout first and the server stamps an ssh_expiry when SSH
        // is enabled, so a window opened for troubleshooting closes itself. set_ssh_enabled_timeout is
        // itself a pool-wide fan-out call, exactly like enable_ssh/disable_ssh - no need to loop hosts.
        Pool.set_ssh_enabled_timeout(session, pool, 3600);

        // The pool call fans out to every host, so there is no need to loop for the enable itself.
        Pool.enable_ssh(session, pool);
        foreach (var record in Host.get_all_records(session).Values)
            Console.WriteLine($"{record.name_label}: ssh enabled={record.ssh_enabled}, "
                              + $"expires {record.ssh_expiry:u}");

        Pool.disable_ssh(session, pool);
        Console.WriteLine("After disable: " + string.Join(", ",
            Host.get_all_records(session).Values.Select(h => $"{h.name_label}={h.ssh_enabled}")));

        foreach (var (host, (enabled, timeout)) in before)
        {
            Host.set_ssh_enabled_timeout(session, host, timeout);   // first: enabling stamps the expiry from it
            if (enabled) Host.enable_ssh(session, host);
        }
        Console.WriteLine("OK: manage-ssh-access");
        session.logout();
    }
}
