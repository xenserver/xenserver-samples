using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a risky
    /// change.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.SnapshotRevert("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void SnapshotRevert(string url, string user, string password,
        string vmName, string snapshotName = "sdk-example-snapshot")
    {
        var session = Connect(url, user, password);
        var vmRef = VmByName(session, vmName);
        Console.WriteLine($"Snapshotting VM: {VM.get_name_label(session, vmRef)}");
        var wasRunning = VM.get_power_state(session, vmRef) == vm_power_state.Running;

        var snapRef = VM.snapshot(session, vmRef, snapshotName).opaque_ref;
        Console.WriteLine($"Created snapshot: {VM.get_uuid(session, snapRef)}");

        // A client shows a thumbnail of what was on screen when the snapshot was taken, captured from the
        // VM's console at that moment. It is an HTTP transfer alongside the API, not an API call, so the
        // session id travels in the query string. ref names the VM's VNC (rfb) console (the VM itself
        // works too). Only a running VM has a console to capture, and a host that can't reach it answers
        // 404 or 500 instead of an image: the picture is incidental, so carry on.
        if (VM.get_power_state(session, vmRef) == vm_power_state.Running)
        {
            var console = VM.get_consoles(session, vmRef)
                .First(c => XenAPI.Console.get_protocol(session, c.opaque_ref) == console_protocol.rfb);
            using var client = InsecureHttpClient();
            var response = client.GetAsync(
                $"{url}/vncsnapshot?session_id={session.opaque_ref}&ref={console.opaque_ref}").Result;
            Console.WriteLine(response.IsSuccessStatusCode
                ? $"Thumbnail:      {response.Content.ReadAsByteArrayAsync().Result.Length} bytes of PNG"
                : $"Thumbnail:      none (the host answered HTTP {(int)response.StatusCode})");
        }
        else
        {
            Console.WriteLine("Thumbnail:      none (the VM is not running, so it has no console)");
        }

        // Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-down a running VM
        // before reverting it), even if it was Running a moment ago - restart it afterwards if that's
        // how we found it, so the workflow actually restores what it changed.
        VM.revert(session, snapRef);
        Console.WriteLine("Reverted VM to the snapshot.");

        if (wasRunning)
        {
            VM.start(session, vmRef, false, true);
            Console.WriteLine("Restarted the VM (it was running before the revert).");
        }

        DestroyVmAndDisks(session, snapRef);
        Console.WriteLine("OK: snapshot-revert");
        session.logout();
    }
}
