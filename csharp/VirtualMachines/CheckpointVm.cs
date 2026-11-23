using System;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you
    /// would before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must have a
    /// guest OS with PV drivers (vm_name).
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CheckpointVm("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void CheckpointVm(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);
        // A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
        // Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest
        // freezes its processes and suspends itself. A guest that is still booting can fail to freeze a
        // process that is busy starting up, and it then abandons the suspend without telling the host, which
        // waits until VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here.
        var vm = VmByName(session, vmName);
        if (VM.get_power_state(session, vm) != vm_power_state.Running)
            throw new InvalidOperationException($"{vmName} must be running to be checkpointed");
        // Running is not enough: the VM may have just been started (or restarted, as snapshot-revert does), so
        // wait for its guest to finish booting first.
        WaitForGuestAgent(session, vm);

        var checkpoint = VM.checkpoint(session, vm, "sdk-example-checkpoint-1");
        Console.WriteLine($"Created checkpoint: {VM.get_uuid(session, checkpoint)}");
        Console.WriteLine($"is_a_snapshot = {VM.get_is_a_snapshot(session, checkpoint)}");

        // A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
        // VM.revert restores exactly that - so the VM is Suspended here, not Running as it was before the
        // checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.resume picks up from there
        // (and frees that memory image).
        VM.revert(session, checkpoint);
        Console.WriteLine($"Reverted {vmName} to the checkpoint; power state now: {VM.get_power_state(session, vm)}");
        VM.resume(session, vm, false, true);
        Console.WriteLine($"Resumed {vmName}; power state now: {VM.get_power_state(session, vm)}");

        // Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
        DestroyVmAndDisks(session, checkpoint);
        Console.WriteLine("Deleted the checkpoint.");
        Console.WriteLine("OK: checkpoint-vm");
        session.logout();
    }
}
