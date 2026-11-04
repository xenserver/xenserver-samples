using System.Collections.Generic;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Create a fresh virtual disk on a storage repository and attach it to a VM.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.AttachDisk("https://xenserver", "root", password, "Rocky Linux 8", "Shared NFS");
    /// </code>
    /// </example>
    public static void AttachDisk(string url, string user, string password,
        string templateName, string srName, string newVmName = "sdk-example-attachdisk")
    {
        const long GiB = 1024L * 1024 * 1024;
        var session = Connect(url, user, password);
        var vm = VM.clone(session, TemplateByName(session, templateName), newVmName).opaque_ref;
        Provision(session, vm);
        var srRef = SrByName(session, srName);

        // Create a fresh VDI on the SR and attach it as a new VBD (a new virtual disk).
        var vdi = VDI.create(session, new VDI
        {
            name_label = "sdk-example-data-disk",
            SR = new XenRef<SR>(srRef),
            virtual_size = 8 * GiB,
            type = vdi_type.user,
            sharable = false,
            read_only = false,
            other_config = new Dictionary<string, string>(),
        }).opaque_ref;
        var device = VM.get_allowed_VBD_devices(session, vm)[0];
        VBD.create(session, new VBD
        {
            VM = new XenRef<VM>(vm),
            VDI = new XenRef<VDI>(vdi),
            userdevice = device,
            bootable = false,
            mode = vbd_mode.RW,
            type = vbd_type.Disk,
            empty = false,
            other_config = new Dictionary<string, string>(),
            qos_algorithm_type = "",
            qos_algorithm_params = new Dictionary<string, string>(),
        });
        Console.WriteLine($"Attached an 8 GiB disk on {SR.get_name_label(session, srRef)} as device {device}");
        Console.WriteLine($"VM now has {VM.get_VBDs(session, vm).Count} VBD(s)");

        // Tidy up: destroy the VM (which removes its VBDs) and then its disks (VM.destroy leaves VDIs
        // behind), including the one just attached.
        DestroyVmAndDisks(session, vm);
        Console.WriteLine("OK: attach-disk");
        session.logout();
    }
}
