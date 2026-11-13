using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Deactivate a running VM's disk, resize it, reactivate it.
    /// </summary>
    public static void ManageVmDisks(string url, string user, string password,
        string sourceVm, string srName, string newVmName = "sdk-example-vm-disks")
    {
        const long GiB = 1024L * 1024 * 1024;
        var session = Connect(url, user, password);
        // Not the VM's root/boot disk: a real VM's system disk is unpluggable=false (only a template's
        // non-system disks default to unpluggable), so VBD.unplug on it fails on a real host with
        // VBD_NOT_UNPLUGGABLE - and the VM has to be running in the first place, or unplug fails with
        // VM_BAD_POWER_STATE. Work on a data disk this example adds to its own throwaway VM instead.
        //
        // Plugging and unplugging a disk on a running VM needs the guest's PV drivers
        // (VM_MISSING_PV_DRIVERS otherwise), so the VM is a throwaway copy of sourceVm, a VM with a
        // guest OS and PV drivers.
        var vmRef = CopyOfGuest(session, sourceVm, newVmName);
        VM.start(session, vmRef, false, true);
        WaitForGuestAgent(session, vmRef);

        var srRef = SrByName(session, srName);
        var vdiRef = VDI.create(session, new VDI
        {
            name_label = "sdk-example-data-disk",
            SR = srRef,
            virtual_size = 4 * GiB,
            type = vdi_type.user,
            sharable = false,
            read_only = false,
            other_config = new Dictionary<string, string>(),
        });
        var vbdRef = VBD.create(session, new VBD
        {
            VM = vmRef,
            VDI = vdiRef,
            userdevice = VM.get_allowed_VBD_devices(session, vmRef)[0],
            bootable = false,
            mode = vbd_mode.RW,
            type = vbd_type.Disk,
            empty = false,
            other_config = new Dictionary<string, string>(),
            qos_algorithm_type = "",
            qos_algorithm_params = new Dictionary<string, string>(),
        });
        VBD.plug(session, vbdRef);
        Console.WriteLine($"Disk attached:  {VBD.get_currently_attached(session, vbdRef)}");

        // Deactivate = VBD.unplug. The disk stays with the VM; it is just no longer live.
        VBD.unplug(session, vbdRef);
        Console.WriteLine($"After unplug:   {VBD.get_currently_attached(session, vbdRef)}");

        var size = VDI.get_virtual_size(session, vdiRef);
        VDI.resize(session, vdiRef, size * 2);
        Console.WriteLine($"Resized:        {size} -> {VDI.get_virtual_size(session, vdiRef)} bytes");

        VBD.plug(session, vbdRef);
        Console.WriteLine($"After plug:     {VBD.get_currently_attached(session, vbdRef)}");

        // Growing a disk that is attached and live is a DIFFERENT call, not a flag on the same one:
        // resize_online tells the storage layer the guest is using the disk while it grows. Only some
        // storage drivers can (none of a stock XenServer 9's do), and the rest refuse with
        // SR_OPERATION_NOT_SUPPORTED - so ask the SR's driver (its SM record's features) first.
        var srType = SR.get_type(session, srRef);
        var features = SM.get_all_records(session).Values
            .FirstOrDefault(r => r.type == srType)?.features ?? new Dictionary<string, long>();
        if (features.ContainsKey("VDI_RESIZE_ONLINE"))
        {
            var grown = VDI.get_virtual_size(session, vdiRef) + GiB;
            VDI.resize_online(session, vdiRef, grown);
            Console.WriteLine($"Grown online:   {VDI.get_virtual_size(session, vdiRef)} bytes");
        }
        else
        {
            Console.WriteLine($"Grown online:   not supported by {srType} storage; unplug, resize, plug as above");
        }

        VM.hard_shutdown(session, vmRef);
        DestroyVmAndDisks(session, vmRef);
        Console.WriteLine("OK: manage-vm-disks");
        session.logout();
    }
}
