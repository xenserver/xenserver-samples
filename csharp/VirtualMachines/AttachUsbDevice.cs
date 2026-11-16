using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it again.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.AttachUsbDevice("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void AttachUsbDevice(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);
        var vm = VM.get_by_name_label(session, vmName)[0];

        // Pick deterministically (lowest description, then uuid), not whatever order the server
        // happens to list them in, so the example behaves the same way every run.
        var pusb = PUSB.get_all_records(session)
            .OrderBy(p => p.Value.description).ThenBy(p => p.Value.uuid).First();
        Console.WriteLine($"Device:         {pusb.Value.description}");

        // Passthrough is off until an administrator enables it on the device — a VUSB.create against a
        // device that has not been released fails rather than silently doing nothing.
        PUSB.set_passthrough_enabled(session, pusb.Key, true);

        var vusb = VUSB.create(session, vm, pusb.Value.USB_group, new Dictionary<string, string>());
        Console.WriteLine($"Attached:       {VM.get_VUSBs(session, vm).Count} device(s)");

        // VUSB.destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM
        // it gets plugged in as soon as it's created, so unplug it first.
        if (VUSB.get_currently_attached(session, vusb)) VUSB.unplug(session, vusb);
        VUSB.destroy(session, vusb);
        Console.WriteLine($"Detached:       {VM.get_VUSBs(session, vm).Count} device(s)");
        PUSB.set_passthrough_enabled(session, pusb.Key, false);
        Console.WriteLine("OK: attach-usb-device");
        session.logout();
    }
}
