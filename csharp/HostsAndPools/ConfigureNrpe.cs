using System;
using System.Collections.Generic;
using System.Linq;
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
        // for pool.enable_ssh - so configure every host in the pool, and restore each one to exactly the
        // state (enabled or not, and its configuration) it was found in afterwards.
        foreach (var host in Host.get_all(session))
        {
            string Nrpe(string fn, Dictionary<string, string> args) =>
                Host.call_plugin(session, host, "nrpe", fn, args);
            var label = Host.get_name_label(session, host);

            // Capture what we're about to change, to put back afterwards.
            var statusBefore = Nrpe("status", new()).Trim();
            var wasEnabled = statusBefore.Split(' ', StringSplitOptions.RemoveEmptyEntries).Last() == "enabled";
            var beforeConfig = new Dictionary<string, string>();
            foreach (var line in Nrpe("get-config", new()).Split('\n'))
            {
                var parts = line.Split(':', 2);
                if (parts.Length == 2 && new[] { "allowed_hosts", "debug", "ssl_logging" }.Contains(parts[0].Trim()))
                    beforeConfig[parts[0].Trim()] = parts[1].Trim();
            }

            Console.WriteLine($"{label}: NRPE status before: {statusBefore}");
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

            // Restore exactly what was found, rather than always disabling: a host that already had
            // NRPE enabled and configured should not be left changed.
            Nrpe("set-config", beforeConfig);
            if (wasEnabled)
                Nrpe("restart", new());
            else
                Nrpe("disable", new());
        }
        Console.WriteLine("OK: configure-nrpe");
        session.logout();
    }
}
