using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Create a VM end to end: pick a template, name the VM, choose an installation source and a home server,
    /// set CPU &amp; memory, add a disk on a storage repository, attach a network interface and start it —
    /// the full sequence, rather than a single clone call.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CreateVmFull("https://xenserver", "root", password, "Rocky Linux 8");
    /// </code>
    /// </example>
    public static void CreateVmFull(string url, string user, string password,
        string templateName, string newVmName = "sdk-example-full-vm")
    {
        const long GiB = 1024L * 1024 * 1024, MiB = 1024L * 1024;

        var session = Connect(url, user, password);
        // Step 1 - Template.
        var templateRef = TemplateByName(session, templateName);
        Console.WriteLine($"Template:      {VM.get_name_label(session, templateRef)}");

        // Step 2 - Name and description.
        var vm = VM.clone(session, templateRef, newVmName).opaque_ref;
        VM.set_name_description(session, vm, "Created by the create-vm-full example");
        VM.set_is_a_template(session, vm, false);
        Console.WriteLine($"Created VM:    {VM.get_uuid(session, vm)}");

        // Step 3 - Installation media (a network install repository).
        VM.add_to_other_config(session, vm, "install-repository", "http://mirror.example.com/rocky/9/os/x86_64");
        Console.WriteLine("Install media: network repository");

        // Step 4 - Home server (affinity).
        var (hostRef, host) = Host.get_all_records(session).First();
        VM.set_affinity(session, vm, hostRef.opaque_ref);
        Console.WriteLine($"Home server:   {host.name_label}");

        // Step 5 - CPU & Memory.
        VM.set_VCPUs_max(session, vm, 2);
        VM.set_VCPUs_at_startup(session, vm, 2);
        VM.set_memory_limits(session, vm, 512 * MiB, 2 * GiB, 2 * GiB, 2 * GiB);
        Console.WriteLine("CPU/memory:    2 vCPUs, 2 GiB");

        // Step 6 - Storage: add a disk on a (non-ISO) SR.
        var (srRef, sr) = SR.get_all_records(session)
            .First(kv => kv.Value.content_type != "iso" && kv.Value.type != "iso" && kv.Value.type != "udev");
        var vbdDevice = VM.get_allowed_VBD_devices(session, vm)[0];
        var vdi = VDI.create(session, new VDI
        {
            name_label = $"{newVmName} disk 0",
            name_description = "System disk created by the create-vm-full example",
            SR = srRef,
            virtual_size = 24 * GiB,
            type = vdi_type.system,
            sharable = false,
            read_only = false,
            other_config = new Dictionary<string, string>(),
        }).opaque_ref;
        VBD.create(session, new VBD
        {
            VM = new XenRef<VM>(vm),
            VDI = new XenRef<VDI>(vdi),
            userdevice = vbdDevice,
            bootable = true,
            mode = vbd_mode.RW,
            type = vbd_type.Disk,
            empty = false,
            other_config = new Dictionary<string, string>(),
            qos_algorithm_type = "",
            qos_algorithm_params = new Dictionary<string, string>(),
        });
        Console.WriteLine($"Storage:       24 GiB disk on {sr.name_label}");

        // Step 7 - Networking: attach a VIF to a network.
        var (netRef, net) = Network.get_all_records(session).First();
        var vifDevice = VM.get_allowed_VIF_devices(session, vm)[0];
        VIF.create(session, new VIF
        {
            VM = new XenRef<VM>(vm),
            network = netRef,
            device = vifDevice,
            MAC = "",
            MTU = 1500,
            other_config = new Dictionary<string, string>(),
            qos_algorithm_type = "",
            qos_algorithm_params = new Dictionary<string, string>(),
        });
        Console.WriteLine($"Networking:    NIC on {net.name_label}");

        // Step 8 - Finish: start the VM.
        VM.start(session, vm, false, true);

        Console.WriteLine("--- Result ---");
        Console.WriteLine($"power state:   {VM.get_power_state(session, vm)}");
        Console.WriteLine($"vCPUs:         {VM.get_VCPUs_max(session, vm)}");
        Console.WriteLine($"disks:         {VM.get_VBDs(session, vm).Count}, NICs: {VM.get_VIFs(session, vm).Count}");

        // Tidy up so the example is repeatable.
        VM.hard_shutdown(session, vm);
        VM.destroy(session, vm);
        VDI.destroy(session, vdi);
        Console.WriteLine("Cleaned up the example VM.");

        Console.WriteLine("OK: create-vm-full");
        session.logout();
    }
}
