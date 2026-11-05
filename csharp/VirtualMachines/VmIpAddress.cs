using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.VmIpAddress("https://xenserver", "root", password);
    /// </code>
    /// </example>
    /// <remarks>
    /// A VM that has only just started may not have reported in yet (no guest_metrics at all, or an empty
    /// networks map) - retry for a while rather than giving up on the first look.
    /// </remarks>
    public static void VmIpAddress(string url, string user, string password,
        int timeoutSeconds = 60, int intervalSeconds = 2)
    {
        var session = Connect(url, user, password);
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (true)
        {
            // A running guest reports its IP in networks, keyed "<vif device>/ip" (e.g. "0/ip"). Not every
            // running VM has one (no guest tools, no NIC, still booting), so look at each until one does.
            VM vm = null;
            string ip = null;
            foreach (var v in VM.get_all_records(session).Values.Where(v =>
                         v.power_state == vm_power_state.Running && !v.is_a_template && !v.is_control_domain
                         && v.guest_metrics.opaque_ref != "OpaqueRef:NULL"))
            {
                if (VM_guest_metrics.get_record(session, v.guest_metrics).networks.TryGetValue("0/ip", out ip)
                    && !string.IsNullOrEmpty(ip))
                {
                    vm = v;
                    break;
                }
            }
            if (vm != null)
            {
                Console.WriteLine($"  {vm.name_label}: {ip}");
                break;
            }
            if (DateTime.UtcNow > deadline)
                throw new Exception($"no running guest reported an IP address within {timeoutSeconds}s");
            System.Threading.Thread.Sleep(intervalSeconds * 1000);
        }
        Console.WriteLine("OK: vm-ip-address");
        session.logout();
    }
}
