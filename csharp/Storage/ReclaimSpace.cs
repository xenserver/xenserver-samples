using System;
using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable SR,
    /// pick a host with a live connection to it, and run the trim operation.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ReclaimSpace("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ReclaimSpace(string url, string user, string password)
    {
        const long GiB = 1024L * 1024 * 1024;
        var session = Connect(url, user, password);
        // Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
        var trimTypes = SM.get_all_records(session).Values
            .Where(sm => sm.features.ContainsKey("SR_TRIM")).Select(sm => sm.type).ToHashSet();
        var srEntry = SR.get_all_records(session)
            .First(kv => kv.Value.physical_size > 0 && trimTypes.Contains(kv.Value.type));
        var srRef = srEntry.Key;
        var sr = srEntry.Value;
        // A host with a currently-attached PBD can reach the SR to run the plugin.
        var host = sr.PBDs.Select(r => PBD.get_record(session, r))
            .First(pbd => pbd.currently_attached).host;

        Console.WriteLine($"  {sr.name_label}: {sr.physical_utilisation / GiB} / {sr.physical_size / GiB} GiB used");

        var args = new Dictionary<string, string> { ["sr_uuid"] = sr.uuid };
        var result = Host.call_plugin(session, host, "trim", "do_trim", args);
        Console.WriteLine($"  reclaimed freed space on {sr.name_label}: {result}");
        // Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
        if (!string.Equals(result.Trim(), "true", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException($"trim plugin returned '{result}'");

        // Rescan to refresh utilisation from the backend, the same way SrUsage does, before reporting it.
        SR.scan(session, srRef);
        var usedAfter = SR.get_physical_utilisation(session, srRef);
        Console.WriteLine($"  {sr.name_label}: {usedAfter / GiB} / {sr.physical_size / GiB} GiB used");
        Console.WriteLine("OK: reclaim-space");
        session.logout();
    }
}
