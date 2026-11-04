using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Move a disk between VMs by detaching and re-attaching it, without copying the data.
    /// </summary>
    public static void AttachExistingDisk(string url, string user, string password)
    {
        const long GiB = 1024L * 1024 * 1024;
        var session = Connect(url, user, password);

        // A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk between
        // VMs is removing one VBD and creating another — no copying, and the data stays where it is.
        var halted = VM.get_all_records(session)
            .Where(kv => !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot
                         && kv.Value.power_state == vm_power_state.Halted)
            .Select(kv => kv.Key.opaque_ref).ToList();

        var sr = SR.get_all_records(session).First(kv =>
            kv.Value.shared && kv.Value.content_type != "iso"
            && kv.Value.type != "iso" && kv.Value.type != "udev").Key.opaque_ref;
        var vdi = VDI.create(session, new VDI
        {
            name_label = "sdk-example-portable-disk",
            SR = new XenRef<SR>(sr),
            virtual_size = 4 * GiB,
            type = vdi_type.user,
            sharable = false,
            read_only = false,
            other_config = new Dictionary<string, string>(),
        }).opaque_ref;
        Console.WriteLine($"Disk {VDI.get_name_label(session, vdi)} created on "
                          + SR.get_name_label(session, sr));

        var vbd = AttachVdi(session, halted[0], vdi);
        Console.WriteLine($"  attached to {VM.get_name_label(session, halted[0])}");

        // Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
        VBD.destroy(session, vbd);
        Console.WriteLine($"  detached:   the disk still exists ({VDI.get_virtual_size(session, vdi)} bytes)");

        AttachVdi(session, halted[1], vdi);
        Console.WriteLine($"  attached to {VM.get_name_label(session, halted[1])}");
        Console.WriteLine($"  the disk is on {VDI.get_VBDs(session, vdi).Count} VM(s)");

        foreach (var r in VDI.get_VBDs(session, vdi)) VBD.destroy(session, r.opaque_ref);
        VDI.destroy(session, vdi);
        Console.WriteLine("OK: attach-existing-disk");
        session.logout();
    }

    /// <summary>Join an existing disk to a VM on its next free device slot.</summary>
    private static string AttachVdi(Session session, string vm, string vdi) => VBD.create(session, new VBD
    {
        VM = new XenRef<VM>(vm),
        VDI = new XenRef<VDI>(vdi),
        userdevice = VM.get_allowed_VBD_devices(session, vm).First(),
        bootable = false,
        mode = vbd_mode.RW,
        type = vbd_type.Disk,
        empty = false,
        other_config = new Dictionary<string, string>(),
        qos_algorithm_type = "",
        qos_algorithm_params = new Dictionary<string, string>(),
    }).opaque_ref;
}
