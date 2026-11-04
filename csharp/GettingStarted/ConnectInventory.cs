using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual
    /// machines with their power state. This is the starting point for every session.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConnectInventory("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ConnectInventory(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all_records(session).Values.First();
        Console.WriteLine($"Connected to pool: {pool.name_label}");

        var hosts = Host.get_all_records(session);
        Console.WriteLine($"Hosts ({hosts.Count}):");
        foreach (var host in hosts.Values)
            Console.WriteLine($"  - {host.name_label} ({host.address})");

        var vms = VM.get_all_records(session).Values
            .Where(v => !v.is_a_template && !v.is_control_domain).ToList();
        Console.WriteLine($"VMs ({vms.Count}):");
        foreach (var vm in vms)
            Console.WriteLine($"  - {vm.name_label} [{vm.power_state}]");

        Console.WriteLine("OK: connect-inventory");
        session.logout();
    }
}
