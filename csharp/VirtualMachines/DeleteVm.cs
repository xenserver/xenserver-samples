using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are destroyed
    /// explicitly afterward.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.DeleteVm("https://xenserver", "root", password, "Rocky Linux 8");
    /// </code>
    /// </example>
    public static void DeleteVm(string url, string user, string password,
        string templateName, string newVmName = "sdk-example-delete")
    {
        var session = Connect(url, user, password);
        // Make a throwaway VM to delete. VM.destroy removes the VM but leaves its disks, so the
        // owned VDIs are destroyed explicitly afterward.
        var vm = VM.clone(session, TemplateByName(session, templateName), newVmName);
        Provision(session, vm);
        var uuid = VM.get_uuid(session, vm);
        var vdis = DiskVdis(session, vm);
        Console.WriteLine($"Deleting VM {uuid} with {vdis.Count} disk(s)");

        VM.destroy(session, vm);
        foreach (var vdi in vdis) VDI.destroy(session, vdi);

        var stillThere = VM.get_all_records(session).Values.Any(v => v.uuid == uuid);
        Console.WriteLine($"VM still present: {stillThere}");
        Console.WriteLine("OK: delete-vm");
        session.logout();
    }
}
