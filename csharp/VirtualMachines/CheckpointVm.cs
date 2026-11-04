using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you
    /// would before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works on a
    /// throwaway copy of a VM with a guest OS and PV drivers (source_vm).
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CheckpointVm("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void CheckpointVm(string url, string user, string password,
        string sourceVm, string newVmName = "sdk-example-checkpoint")
    {
        var session = Connect(url, user, password);
        // A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
        // Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), hence a
        // copy of sourceVm - a VM with a guest OS and PV drivers - rather than an OS-less template
        // clone.
        var vm = CopyOfGuest(session, sourceVm, newVmName);
        VM.start(session, vm, false, true);
        WaitForGuestAgent(session, vm);

        var checkpoint = VM.checkpoint(session, vm, "sdk-example-checkpoint-1").opaque_ref;
        Console.WriteLine($"Created checkpoint: {VM.get_uuid(session, checkpoint)}");
        Console.WriteLine($"is_a_snapshot = {VM.get_is_a_snapshot(session, checkpoint)}");

        // A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
        // VM.revert restores exactly that - so the VM is Suspended here, not Running as it was before
        // the checkpoint, with a suspend_VDI holding the checkpoint's memory image. Always resume
        // (never a bare "if Running: hard_shutdown" check, which never fires since the VM is never
        // Running here) before destroying it, or the suspend_VDI leaks as a storage orphan.
        VM.revert(session, checkpoint);
        Console.WriteLine($"Reverted the VM to the checkpoint; power state now: {VM.get_power_state(session, vm)}");
        VM.resume(session, vm, false, true);

        // Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
        DestroyVmAndDisks(session, checkpoint);
        VM.hard_shutdown(session, vm);
        DestroyVmAndDisks(session, vm);
        Console.WriteLine("OK: checkpoint-vm");
        session.logout();
    }
}
