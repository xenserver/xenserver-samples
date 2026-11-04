using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks) —
    /// distinct from a fast, copy-on-write clone.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CopyVm("https://xenserver", "root", password, "db-01", "Shared NFS");
    /// </code>
    /// </example>
    public static void CopyVm(string url, string user, string password,
        string vmName, string srName, string copyName = "sdk-example-copy")
    {
        var session = Connect(url, user, password);
        // A full copy needs a halted source; it places an independent set of disks on the chosen SR.
        // VM.copy (like VM.clone) raises VM_BAD_POWER_STATE on a running source, so shut it down first
        // if it's running, and start it back up again after the copy.
        var source = VmByName(session, vmName);
        var (srRef, sr) = SR.get_all_records(session).First(kv => kv.Value.name_label == srName);
        Console.WriteLine($"Copying '{VM.get_name_label(session, source)}' to SR: {sr.name_label}");

        var wasRunning = VM.get_power_state(session, source) == vm_power_state.Running;
        if (wasRunning) VM.clean_shutdown(session, source);

        var copy = VM.copy(session, source, copyName, srRef).opaque_ref;
        Console.WriteLine($"Copied VM:     {VM.get_uuid(session, copy)}");
        Console.WriteLine($"Copy has {VM.get_VBDs(session, copy).Count} VBD(s), is_a_template = {VM.get_is_a_template(session, copy)}");

        if (wasRunning) VM.start(session, source, false, true);

        // Tidy up: destroy the copy and its disks, leaving the source VM intact.
        DestroyVmAndDisks(session, copy);
        Console.WriteLine("Cleaned up the copied VM (left the source intact).");
        Console.WriteLine("OK: copy-vm");
        session.logout();
    }
}
