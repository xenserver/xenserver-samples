using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the
    /// ordering rule the four bounds must obey enforced.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureDynamicMemory("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ConfigureDynamicMemory(string url, string user, string password)
    {
        var session = Connect(url, user, password);

        var vm = VM.get_all_records(session).First(kv =>
            !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot &&
            kv.Value.power_state == vm_power_state.Halted);
        var before = vm.Value;
        Console.WriteLine($"{before.name_label}: static {Gib(before.memory_static_min)}-"
                          + $"{Gib(before.memory_static_max)}, dynamic {Gib(before.memory_dynamic_min)}-"
                          + $"{Gib(before.memory_dynamic_max)}");

        // Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
        // static maximum for every supported guest (lower can make it unstable), and never below the static
        // floor, which is the least the guest can boot in.
        var floor = Math.Max(before.memory_static_min, before.memory_static_max * 3 / 4);
        var ceiling = before.memory_static_max;
        VM.set_memory_dynamic_range(session, vm.Key, floor, ceiling);
        Console.WriteLine($"  dynamic range now {Gib(VM.get_memory_dynamic_min(session, vm.Key))}-"
                          + $"{Gib(VM.get_memory_dynamic_max(session, vm.Key))}");

        // The ordering is enforced, not advisory: a range wider than the static bounds is refused rather
        // than quietly clamped.
        try
        {
            VM.set_memory_dynamic_range(session, vm.Key, floor, ceiling * 2);
            Console.WriteLine("  ERROR: an out-of-range maximum was accepted");
        }
        catch (Failure failure)
        {
            Console.WriteLine($"  refused a dynamic_max above static_max: {failure.ErrorDescription[0]}");
        }

        VM.set_memory_dynamic_range(session, vm.Key,
            before.memory_dynamic_min, before.memory_dynamic_max);
        Console.WriteLine("OK: configure-dynamic-memory");
        session.logout();
    }

    private static string Gib(long bytes) => $"{bytes / (1024.0 * 1024 * 1024):F1} GiB";
}
