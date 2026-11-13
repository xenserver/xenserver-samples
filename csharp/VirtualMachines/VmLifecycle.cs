using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down
    /// cleanly. Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy of
    /// a VM with a guest OS and PV drivers (source_vm), which is deleted again with its disks afterwards.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.VmLifecycle("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void VmLifecycle(string url, string user, string password,
        string sourceVm, string newVmName = "sdk-example-lifecycle")
    {
        var session = Connect(url, user, password);
        // Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV
        // drivers), so the copy is made from sourceVm, a VM with a guest OS and PV drivers, and the
        // example waits for the guest to report in after starting. Suspend also needs a suspend-image
        // SR (the VM's own, else the pool's, else the host's); check one is actually configured before
        // trying.
        var vmRef = CopyOfGuest(session, sourceVm, newVmName);

        string State() => VM.get_power_state(session, vmRef).ToString();

        Console.WriteLine($"Initial power state: {State()}");
        VM.start(session, vmRef, false, true);
        WaitForGuestAgent(session, vmRef);
        Console.WriteLine($"After start:    {State()}");

        // The emulated hardware (the device model) can be restarted under a running guest without
        // rebooting it — what you reach for when the VM's virtual devices misbehave.
        VM.restart_device_models(session, vmRef);
        Console.WriteLine($"Device models restarted; still {State()}");

        if (HasSuspendSr(session, vmRef))
        {
            VM.suspend(session, vmRef);
            Console.WriteLine($"After suspend:  {State()}");
            VM.resume(session, vmRef, false, true);
            WaitForGuestAgent(session, vmRef); // the PV drivers reconnect after a resume
            Console.WriteLine($"After resume:   {State()}");
        }
        else
        {
            Console.WriteLine("Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host");
        }

        // A clean shutdown asks the guest OS to shut itself down, as pressing the power button would.
        VM.clean_shutdown(session, vmRef);
        Console.WriteLine($"After shutdown: {State()}");

        DestroyVmAndDisks(session, vmRef);
        Console.WriteLine("OK: vm-lifecycle");
        session.logout();
    }

    /// <summary>
    /// Whether VM.suspend has a suspend-image SR to use: the VM's own, else the pool's, else the
    /// resident host's - the same fallback order xapi's choose_suspend_sr uses.
    /// </summary>
    private static bool HasSuspendSr(Session session, XenRef<VM> vm)
    {
        if (!Helper.IsNullOrEmptyOpaqueRef(VM.get_suspend_SR(session, vm))) return true;
        var pool = Pool.get_all(session)[0];
        if (!Helper.IsNullOrEmptyOpaqueRef(Pool.get_suspend_image_SR(session, pool))) return true;
        var host = Pool.get_master(session, pool);
        return !Helper.IsNullOrEmptyOpaqueRef(Host.get_suspend_image_sr(session, host));
    }
}
