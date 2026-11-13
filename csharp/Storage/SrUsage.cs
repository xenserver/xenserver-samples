using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Report each storage repository's used and total capacity, and rescan one.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.SrUsage("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void SrUsage(string url, string user, string password)
    {
        const long GiB = 1024L * 1024 * 1024;
        var session = Connect(url, user, password);
        foreach (var sr in SR.get_all_records(session).Values.OrderBy(s => s.name_label))
        {
            if (sr.physical_size <= 0) continue; // skip ISO/DVD pseudo-SRs
            Console.WriteLine($"  {sr.name_label}: {sr.physical_utilisation / GiB} / {sr.physical_size / GiB} GiB used");
        }
        // A rescan refreshes an SR's utilisation from its backend.
        var scanMe = SR.get_all_records(session).First(kv => kv.Value.physical_size > 0).Key;
        SR.scan(session, scanMe);
        Console.WriteLine("OK: sr-usage");
        session.logout();
    }
}
