using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Enumerate the pool's networks with their physical and virtual interface counts.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ListNetworks("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ListNetworks(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var nets = Network.get_all_records(session).Values.OrderBy(n => n.name_label).ToList();
        Console.WriteLine($"Networks ({nets.Count}):");
        foreach (var net in nets)
            Console.WriteLine($"  - {net.name_label}: {net.PIFs.Count} PIF(s), {net.VIFs.Count} VIF(s)");
        Console.WriteLine("OK: list-networks");
        session.logout();
    }
}
