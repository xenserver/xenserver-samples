using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ReadMetrics("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ReadMetrics(string url, string user, string password)
    {
        const long MiB = 1024L * 1024;
        var session = Connect(url, user, password);
        var (hostRef, host) = Host.get_all_records(session).First();
        var hm = Host.get_metrics(session, hostRef);
        Console.WriteLine($"Host {host.name_label}: " +
            $"{Host_metrics.get_memory_total(session, hm) / MiB} MiB total, " +
            $"{Host.compute_free_memory(session, hostRef) / MiB} MiB free, " +
            $"live = {Host_metrics.get_live(session, hm)}");

        var vm = VM.get_all_records(session).First(kv => !kv.Value.is_a_template
            && !kv.Value.is_control_domain && kv.Value.power_state == vm_power_state.Running).Key;
        var vmm = VM.get_metrics(session, vm);
        Console.WriteLine($"VM {VM.get_name_label(session, vm)}: " +
            $"{VM_metrics.get_VCPUs_number(session, vmm)} vCPU(s), " +
            $"{VM_metrics.get_memory_actual(session, vmm) / MiB} MiB");
        Console.WriteLine("OK: read-metrics");
        session.logout();
    }
}
