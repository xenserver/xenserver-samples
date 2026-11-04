using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Move a running VM's virtual disk to a different storage repository while the VM keeps running — live
    /// storage migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.StorageMigrate("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void StorageMigrate(string url, string user, string password,
        string sourceVm, string newVmName = "sdk-example-storagemigrate")
    {
        var session = Connect(url, user, password);
        // Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV
        // drivers), so this works on a throwaway copy of sourceVm, a VM with a guest OS and PV drivers.
        // (A halted VM's disk moves too, without the guest; what VDI.pool_migrate always needs is a VM
        // to move the disk for - a VDI no VBD points at fails VDI_NEEDS_VM_FOR_MIGRATE.)
        var vm = CopyOfGuest(session, sourceVm, newVmName);
        VM.start(session, vm, false, true);
        WaitForGuestAgent(session, vm);
        var vdi = DiskVdis(session, vm).First();
        var sourceSr = VDI.get_SR(session, vdi).opaque_ref;
        Console.WriteLine($"Disk is on SR: {SR.get_name_label(session, sourceSr)}");

        // Pick a different SR that holds disks and that the VM's host can reach (an attached PBD
        // there).
        var host = VM.get_resident_on(session, vm).opaque_ref;
        var destSr = SR.get_all_records(session)
            .First(kv => kv.Key.opaque_ref != sourceSr && kv.Value.content_type != "iso"
                && kv.Value.type != "iso" && kv.Value.type != "udev"
                && kv.Value.PBDs.Any(pbd => PBD.get_host(session, pbd.opaque_ref).opaque_ref == host
                    && PBD.get_currently_attached(session, pbd.opaque_ref))).Key.opaque_ref;
        // pool_migrate returns the disk's new VDI: the copy on the destination SR replaces the
        // original. Copying a disk takes minutes, so run it as a task (see AwaitTask).
        vdi = AwaitTask(session, VDI.async_pool_migrate(session, vdi, destSr, new Dictionary<string, string>()));

        var nowOn = VDI.get_SR(session, vdi).opaque_ref;
        Console.WriteLine($"Disk moved to:  {SR.get_name_label(session, nowOn)}");

        // Tidy up: the VM and the disks it now owns.
        VM.hard_shutdown(session, vm);
        DestroyVmAndDisks(session, vm);
        Console.WriteLine("OK: storage-migrate");
        session.logout();
    }
}
