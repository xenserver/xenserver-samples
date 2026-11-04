using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running guests to
    /// another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and PV drivers
    /// (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation something to
    /// move.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.HostMaintenance("https://xenserver", "root", password, "web-01", "Shared NFS");
    /// </code>
    /// </example>
    public static void HostMaintenance(string url, string user, string password,
        string sourceVm, string srName, string newVmName = "sdk-example-maint")
    {
        var session = Connect(url, user, password);
        // Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
        var master = Pool.get_all_records(session).Values.First().master.opaque_ref;
        var hostRef = Host.get_all_records(session).Keys.First(h => h.opaque_ref != master).opaque_ref;
        Console.WriteLine($"Maintenance host: {Host.get_name_label(session, hostRef)}");

        // Pin a throwaway copy of sourceVm to that host so evacuation has something to move.
        // Evacuation live-migrates the guest, which needs its cooperation (VM_LACKS_FEATURE without PV
        // drivers), so sourceVm must have a guest OS with PV drivers. Evacuation also needs somewhere
        // else in the pool that can actually see the VM's disk - a VM whose only disk is on local
        // (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a pool's installation-time
        // default SR is commonly local storage, so put the pinned VM's disk on a shared SR explicitly.
        var vm = CopyOfGuest(session, sourceVm, newVmName);
        MoveDisksToSr(session, vm, SrByName(session, srName, shared: true));
        VM.set_affinity(session, vm, hostRef);
        VM.start(session, vm, false, true);
        WaitForGuestAgent(session, vm);
        Console.WriteLine($"Guest resident on:{Host.get_name_label(session, VM.get_resident_on(session, vm).opaque_ref)}");

        // Enter maintenance mode: disable the host, then evacuate its guests.
        Host.disable(session, hostRef);
        Console.WriteLine($"After disable:    host.enabled = {Host.get_enabled(session, hostRef)}");
        Host.evacuate(session, hostRef);
        Console.WriteLine($"After evacuate:   guest now on {Host.get_name_label(session, VM.get_resident_on(session, vm).opaque_ref)}");

        // Exit maintenance mode.
        Host.enable(session, hostRef);
        Console.WriteLine($"After enable:     host.enabled = {Host.get_enabled(session, hostRef)}");

        // Tidy up so the example is repeatable.
        VM.hard_shutdown(session, vm);
        DestroyVmAndDisks(session, vm);
        Console.WriteLine("OK: host-maintenance");
        session.logout();
    }
}
