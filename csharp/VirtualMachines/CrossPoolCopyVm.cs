using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the
    /// destination, then send a copy of the VM from the source. Takes the destination pool's URL as an extra
    /// argument after the password.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CrossPoolCopyVm("https://poolA", "root", password, "https://poolB");
    /// </code>
    /// </example>
    /// <remarks>
    /// Copy a VM from one pool to another (Storage XenMotion copy) — the API behind XenCenter's cross-pool
    /// Copy. Open a session to each pool, get a receiver token from the destination with
    /// host.migrate_receive, then VM.migrate_send with copy=true on the source (which is left intact).
    /// </remarks>
    public static void CrossPoolCopyVm(string url, string user, string password, string destUrl,
        string vmName = "db-01", string destUser = null, string destPassword = null)
    {
        var source = Connect(url, user, password);
        var dest = Connect(destUrl, destUser ?? user, destPassword ?? password);
        // Destination: choose a host, a network and an SR, then ask for a receiver token. The disks go to
        // the destination pool's default SR and the data travels over the host's management network -
        // one both pools can certainly reach (the first network listed may well not be).
        var destPool = Pool.get_all(dest)[0];
        var destHost = Pool.get_master(dest, destPool).opaque_ref;
        var destSr = Pool.get_default_SR(dest, destPool).opaque_ref;
        var managementPif = Host.get_PIFs(dest, destHost).First(pif => PIF.get_management(dest, pif.opaque_ref));
        var destNetwork = PIF.get_network(dest, managementPif.opaque_ref).opaque_ref;
        var receiver = Host.migrate_receive(dest, destHost, destNetwork, new Dictionary<string, string>());

        // Source: map every disk to the destination SR and every NIC to the destination network
        // (a cross-pool copy needs a complete mapping), then send with copy=true.
        var vm = VmByName(source, vmName);
        var vdiMap = new Dictionary<XenRef<VDI>, XenRef<SR>>();
        foreach (var vbdRef in VM.get_VBDs(source, vm))
        {
            if (VBD.get_type(source, vbdRef.opaque_ref) != vbd_type.Disk) continue;
            var vdi = VBD.get_VDI(source, vbdRef.opaque_ref);
            if (vdi.opaque_ref != "OpaqueRef:NULL") vdiMap[vdi] = new XenRef<SR>(destSr);
        }
        var vifMap = new Dictionary<XenRef<VIF>, XenRef<Network>>();
        foreach (var vifRef in VM.get_VIFs(source, vm)) vifMap[vifRef] = new XenRef<Network>(destNetwork);

        var options = new Dictionary<string, string> { ["copy"] = "true" };
        var copy = VM.migrate_send(source, vm, receiver, false, vdiMap, vifMap, options,
            new Dictionary<XenRef<VGPU>, XenRef<GPU_group>>());

        // Copy (not move): the source VM is still on the source pool.
        Console.WriteLine($"Sent '{vmName}' to the destination pool (copy); source still present: " +
                          $"{VmByName(source, vmName) == vm}");
        // The result is the new VM's ref on the DESTINATION pool - use the destination session to read it.
        Console.WriteLine($"  the copy on the destination: {VM.get_name_label(dest, copy)} ({VM.get_uuid(dest, copy)})");

        // Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
        DestroyVmAndDisks(dest, copy.opaque_ref);
        Console.WriteLine("OK: cross-pool-copy-vm");
        source.logout();
        dest.logout();
    }
}
