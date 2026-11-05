using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy —
    /// the quick way to stamp out new VMs from a halted "golden" image.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CloneVm("https://xenserver", "root", password, "db-01");
    /// </code>
    /// </example>
    public static void CloneVm(string url, string user, string password,
        string vmName, string cloneName = "sdk-example-clone")
    {
        var session = Connect(url, user, password);
        // Unlike Copy (a full, independent copy onto a chosen SR), Clone is a fast copy-on-write
        // duplicate on the same SR — ideal for a halted "golden" VM.
        // VM.clone (like VM.copy) raises VM_BAD_POWER_STATE on a running source, so shut it down
        // first if it's running, and start it back up again after the clone.
        var source = VmByName(session, vmName);

        var wasRunning = VM.get_power_state(session, source) == vm_power_state.Running;
        if (wasRunning) VM.clean_shutdown(session, source);

        var clone = VM.clone(session, source, cloneName).opaque_ref;
        Console.WriteLine($"Cloned '{VM.get_name_label(session, source)}' → {VM.get_name_label(session, clone)}");
        Console.WriteLine($"Clone has {VM.get_VBDs(session, clone).Count} VBD(s)");

        if (wasRunning) VM.start(session, source, false, true);

        // Tidy up: destroy the clone and its (owned) disks.
        DestroyVmAndDisks(session, clone);
        Console.WriteLine("OK: clone-vm");
        session.logout();
    }
}
