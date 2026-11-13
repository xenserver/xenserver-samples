using System;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.VmIpAddress("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    /// <remarks>
    /// A VM that has only just started may not have reported in yet (no guest_metrics at all, or an empty
    /// networks map) - retry for a while before concluding it has no guest agent reporting.
    /// </remarks>
    public static void VmIpAddress(string url, string user, string password, string vmName = "web-01",
        int timeoutSeconds = 60, int intervalSeconds = 2)
    {
        var session = Connect(url, user, password);
        var vm = VmByName(session, vmName);
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        string ip = null;
        while (true)
        {
            // An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
            var record = VM.get_record(session, vm);
            if (record.power_state == vm_power_state.Running && !Helper.IsNullOrEmptyOpaqueRef(record.guest_metrics)
                && VM_guest_metrics.get_record(session, record.guest_metrics).networks.TryGetValue("0/ip", out ip)
                && !string.IsNullOrEmpty(ip))
                break;
            ip = null;
            if (DateTime.UtcNow > deadline)
                break;
            System.Threading.Thread.Sleep(intervalSeconds * 1000);
        }
        Console.WriteLine(ip != null
            ? $"  {vmName}: {ip}"
            : $"  {vmName}: no IP address reported yet (no guest agent running?)");
        Console.WriteLine("OK: vm-ip-address");
        session.logout();
    }
}
