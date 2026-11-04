using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.VmFromSnapshot("https://xenserver", "root", password, "db-01");
    /// </code>
    /// </example>
    public static void VmFromSnapshot(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);

        // A snapshot is a VM record with is_a_snapshot (and is_a_template) set, and cloning it gives a
        // custom template that stands on its own while the snapshot stays put.
        var vm = VmByName(session, vmName);
        var snapshot = VM.snapshot(session, vm, "sdk-example-source-snapshot").opaque_ref;
        Console.WriteLine($"Snapshot of {vmName} taken");

        // A clone of a snapshot is a template, not another snapshot: it stands on its own instead of
        // being filed under the original VM. Provision it to get an ordinary VM you can start.
        var newVm = VM.clone(session, snapshot, "sdk-example-vm-from-snapshot").opaque_ref;
        Provision(session, newVm);
        Console.WriteLine($"  new VM:      {VM.get_name_label(session, newVm)} "
                          + $"(is_a_template={VM.get_is_a_template(session, newVm)})");

        // Another clone, left as the template it already is: a starting point to stamp more VMs from.
        var template = VM.clone(session, snapshot, "sdk-example-template-from-snapshot").opaque_ref;
        Console.WriteLine($"  new template:{VM.get_name_label(session, template)} "
                          + $"(is_a_template={VM.get_is_a_template(session, template)})");

        foreach (var r in new[] { newVm, template, snapshot }) DestroyVmAndDisks(session, r);
        Console.WriteLine("OK: vm-from-snapshot");
        session.logout();
    }
}
