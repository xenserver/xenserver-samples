using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.GpuInventory("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void GpuInventory(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var groups = GPU_group.get_all_records(session);
        Console.WriteLine($"GPU groups ({groups.Count}):");
        foreach (var group in groups.Values)
        {
            var types = group.supported_VGPU_types
                .Select(t => VGPU_type.get_model_name(session, t));
            Console.WriteLine($"  - {group.name_label}: {group.PGPUs.Count} pGPU(s), " +
                $"vGPU types: {string.Join(", ", types)}");
        }
        // How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU
        // full before using the next, breadth-first spreads them out.
        var groupRef = groups.Keys.First();
        var beforeAlloc = GPU_group.get_allocation_algorithm(session, groupRef);
        GPU_group.set_allocation_algorithm(session, groupRef, allocation_algorithm.breadth_first);
        Console.WriteLine($"Allocation:      {beforeAlloc} -> {GPU_group.get_allocation_algorithm(session, groupRef)}");
        GPU_group.set_allocation_algorithm(session, groupRef, beforeAlloc);
        Console.WriteLine("OK: gpu-inventory");
        session.logout();
    }
}
