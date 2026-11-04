using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// List a VM's attached disks and the size of each.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.VbdInventory("https://xenserver", "root", password, "db-01");
    /// </code>
    /// </example>
    public static void VbdInventory(string url, string user, string password, string vmName)
    {
        const long GiB = 1024L * 1024 * 1024;
        var session = Connect(url, user, password);
        var vm = VmByName(session, vmName);
        Console.WriteLine($"Disks of '{VM.get_name_label(session, vm)}':");
        foreach (var vbdRef in VM.get_VBDs(session, vm))
        {
            var vbd = VBD.get_record(session, vbdRef.opaque_ref);
            if (vbd.type != vbd_type.Disk) continue;
            var vdi = VBD.get_VDI(session, vbdRef.opaque_ref).opaque_ref;
            var size = vdi == "OpaqueRef:NULL" ? 0 : VDI.get_virtual_size(session, vdi) / GiB;
            Console.WriteLine($"  - device {vbd.userdevice}: {size} GiB");
        }
        Console.WriteLine("OK: vbd-inventory");
        session.logout();
    }
}
