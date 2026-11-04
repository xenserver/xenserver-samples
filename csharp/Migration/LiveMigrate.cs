using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Move a running VM to another host in the pool with no downtime: check the destination can boot it,
    /// live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and PV
    /// drivers (source_vm), with its disks moved first to a shared storage repository (sr_name) so the
    /// destination host can see them.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.LiveMigrate("https://xenserver", "root", password, "web-01", "Shared NFS");
    /// </code>
    /// </example>
    public static void LiveMigrate(string url, string user, string password,
        string sourceVm, string srName, string newVmName = "sdk-example-migrate")
    {
        var session = Connect(url, user, password);
        // Moves a throwaway copy of sourceVm, a VM with a guest OS and PV drivers: live migration
        // needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers). Only the VM's memory
        // moves, so the destination host has to see its disks already: a disk on local storage
        // refuses with VM_REQUIRES_SR. Put the copy's disks on the shared SR srName first.
        var vm = CopyOfGuest(session, sourceVm, newVmName);
        MoveDisksToSr(session, vm, SrByName(session, srName, shared: true));
        VM.start(session, vm, false, true);
        WaitForGuestAgent(session, vm);

        var sourceHost = VM.get_resident_on(session, vm).opaque_ref;
        Console.WriteLine($"VM is running on: {Host.get_name_label(session, sourceHost)}");

        // Pick a different host in the pool to receive the VM.
        var destHost = Host.get_all_records(session).Keys.First(h => h.opaque_ref != sourceHost).opaque_ref;

        // Check the destination can boot it, then live-migrate (empty options = default live migration).
        VM.assert_can_boot_here(session, vm, destHost);
        VM.pool_migrate(session, vm, destHost, new Dictionary<string, string>());

        Console.WriteLine($"Migrated to:      {Host.get_name_label(session, VM.get_resident_on(session, vm).opaque_ref)}");
        Console.WriteLine($"Still running:    {VM.get_power_state(session, vm)}");

        // Tidy up so the example is repeatable.
        VM.hard_shutdown(session, vm);
        DestroyVmAndDisks(session, vm);
        Console.WriteLine("OK: live-migrate");
        session.logout();
    }
}
