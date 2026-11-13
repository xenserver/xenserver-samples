using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureHostStorage("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ConfigureHostStorage(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var host = Pool.get_master(session, Pool.get_all(session)[0]);

        // The IQN identifies this host to iSCSI targets, so a target's access list is written against
        // it — changing it on a host with live iSCSI storage cuts it off. Existing iSCSI SRs must be
        // detached first: changing the IQN underneath them can make the host unable to reconnect to new
        // or existing SRs until the storage target is updated to match. Multipathing uses every path to
        // the storage rather than one, and on real hardware you put the host into maintenance mode
        // before changing it, because the paths are rebuilt.
        var beforeIqn = Host.get_iscsi_iqn(session, host);
        var beforeMultipathing = Host.get_multipathing(session, host);
        Console.WriteLine($"{Host.get_name_label(session, host)}: iSCSI IQN '{beforeIqn}', " +
                          $"multipathing {beforeMultipathing}");

        Host.set_iscsi_iqn(session, host, $"iqn.2026-01.com.example:{Host.get_name_label(session, host)}");
        Host.set_multipathing(session, host, true);
        Console.WriteLine($"  IQN now:      {Host.get_iscsi_iqn(session, host)}");
        Console.WriteLine($"  multipathing: {Host.get_multipathing(session, host)}");

        // set_iscsi_iqn refuses an empty string (INVALID_VALUE); only restore it if this host actually
        // had one set before - a host that has never had an IQN configured has it empty, and there is no
        // way to set it back to empty through this call.
        if (!string.IsNullOrEmpty(beforeIqn)) Host.set_iscsi_iqn(session, host, beforeIqn);
        Host.set_multipathing(session, host, beforeMultipathing);
        Console.WriteLine("  restored");
        Console.WriteLine("OK: configure-host-storage");
        session.logout();
    }
}
