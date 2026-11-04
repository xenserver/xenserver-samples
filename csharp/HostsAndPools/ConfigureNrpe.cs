using System.Collections.Generic;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read its
    /// status and configuration, enable it and permit a monitoring host, then read it back.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureNrpe("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ConfigureNrpe(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        // host.call_plugin is per-host - there is no pool-wide fan-out for plugin calls the way there is
        // for pool.enable_ssh - so configure every host in the pool, and restore each one to disabled
        // again afterwards.
        foreach (var host in Host.get_all(session))
        {
            string Nrpe(string fn, Dictionary<string, string> args) =>
                Host.call_plugin(session, host.opaque_ref, "nrpe", fn, args);
            var label = Host.get_name_label(session, host.opaque_ref);
            Console.WriteLine($"{label}: NRPE status before: {Nrpe("status", new()).Trim()}");
            Nrpe("enable", new());
            Nrpe("set-config", new()
            {
                ["allowed_hosts"] = "127.0.0.1,::1,192.0.2.60",
                ["debug"] = "0",
                ["ssl_logging"] = "0x00",
            });
            Nrpe("restart", new());
            Console.WriteLine($"  status after:  {Nrpe("status", new()).Trim()}");
            foreach (var line in Nrpe("get-config", new()).Split('\n'))
                if (line.StartsWith("allowed_hosts:"))
                    Console.WriteLine($"  allowed hosts: {line.Split(':', 2)[1].Trim()}");
            Nrpe("disable", new()); // restore: leave it as we found it
        }
        Console.WriteLine("OK: configure-nrpe");
        session.logout();
    }
}
