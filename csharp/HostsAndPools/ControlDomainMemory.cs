using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Read and change a host's control domain (dom0) memory, then put it back. One setter pins the static
    /// and dynamic bounds together, because dom0 does not balloon.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ControlDomainMemory("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ControlDomainMemory(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var host = Host.get_all(session)[0];
        var dom0 = Host.get_resident_VMs(session, host.opaque_ref)
            .First(vm => VM.get_is_control_domain(session, vm.opaque_ref));

        var original = VM.get_memory_dynamic_min(session, dom0.opaque_ref);
        Console.WriteLine($"{Host.get_name_label(session, host.opaque_ref)} dom0: "
                          + $"{original / (double)(1024 * 1024 * 1024):F1} GiB");

        // One setter, not a range: dom0 does not balloon, so set_memory pins the static and dynamic
        // bounds and the target together. The new size takes effect at the next reboot, so change
        // it with the host in maintenance mode — the API itself does not stop you.
        VM.set_memory(session, dom0.opaque_ref, original + 1024L * 1024 * 1024);
        var record = VM.get_record(session, dom0.opaque_ref);
        Console.WriteLine($"  now {record.memory_dynamic_min / (double)(1024 * 1024 * 1024):F1} GiB "
                          + $"(static {record.memory_static_min}-{record.memory_static_max}, "
                          + $"dynamic {record.memory_dynamic_min}-{record.memory_dynamic_max})");

        VM.set_memory(session, dom0.opaque_ref, original);   // leave the pool as we found it
        Console.WriteLine("OK: control-domain-memory");
        session.logout();
    }
}
