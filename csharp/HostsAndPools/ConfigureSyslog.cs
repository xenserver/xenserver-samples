using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the setting
    /// is recorded but nothing changes.
    /// </summary>
    public static void ConfigureSyslog(string url, string user, string password,
        string syslogServer = "192.0.2.50")
    {
        var session = Connect(url, user, password);
        var host = Pool.get_master(session, Pool.get_all(session)[0]);

        Console.WriteLine($"{Host.get_name_label(session, host)} logging: {LoggingLabel(session, host)}");

        // Two steps, and the second is the one that is easy to miss: setting the destination only
        // records it, and the host keeps logging locally until the syslog daemon is reconfigured to
        // pick the setting up.
        Host.remove_from_logging(session, host, "syslog_destination");
        Host.add_to_logging(session, host, "syslog_destination", syslogServer);
        Host.syslog_reconfigure(session, host);
        Console.WriteLine($"  now logging to: {Host.get_logging(session, host)["syslog_destination"]}");

        Host.remove_from_logging(session, host, "syslog_destination");
        Host.syslog_reconfigure(session, host);
        Console.WriteLine($"  restored: {LoggingLabel(session, host)}");
        Console.WriteLine("OK: configure-syslog");
        session.logout();
    }

    /// <summary>The host's logging config, or "(local only)" when nothing is configured.</summary>
    private static string LoggingLabel(Session session, XenRef<Host> host)
    {
        var logging = Host.get_logging(session, host);
        return logging.Count == 0 ? "(local only)" : string.Join(", ", logging.Select(kv => $"{kv.Key}={kv.Value}"));
    }
}
