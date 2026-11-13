using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Add a DVD drive to a VM, insert an ISO from the library and eject it again.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ManageVmMedia("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ManageVmMedia(string url, string user, string password)
    {
        var session = Connect(url, user, password);

        var vm = VM.get_all_records(session).First(kv =>
            !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot &&
            kv.Value.power_state == vm_power_state.Halted);
        Console.WriteLine($"Adding a DVD drive to {vm.Value.name_label}");

        // A CD drive is a VBD like any other, distinguished by type=CD; the media is whichever VDI it
        // points at, and an empty drive points at none.
        var device = VM.get_allowed_VBD_devices(session, vm.Key)[0];
        var drive = VBD.create(session, new VBD
        {
            VM = vm.Key,
            VDI = new XenRef<VDI>(Helper.NullOpaqueRef),
            userdevice = device,
            bootable = false,
            mode = vbd_mode.RO,
            type = vbd_type.CD,
            empty = true,
            unpluggable = true,
            other_config = new Dictionary<string, string>(),
            qos_algorithm_type = "",
            qos_algorithm_params = new Dictionary<string, string>(),
        });
        Console.WriteLine($"  drive {device} is empty: {VBD.get_empty(session, drive)}");

        // The ISO library is an SR of content type "iso"; its VDIs are the available images.
        var isoSr = SR.get_all_records(session)
            .First(kv => kv.Value.content_type == "iso" && kv.Value.type != "udev");
        var iso = SR.get_VDIs(session, isoSr.Key)
            .OrderBy(v => VDI.get_name_label(session, v))
            .First();
        Console.WriteLine($"  inserting {VDI.get_name_label(session, iso)}");
        VBD.insert(session, drive, iso);
        Console.WriteLine($"  drive now holds {VDI.get_name_label(session, VBD.get_VDI(session, drive))}"
                          + $" (empty={VBD.get_empty(session, drive)})");

        VBD.eject(session, drive);
        Console.WriteLine($"  after eject, empty={VBD.get_empty(session, drive)}");

        VBD.destroy(session, drive);
        Console.WriteLine("OK: manage-vm-media");
        session.logout();
    }
}
