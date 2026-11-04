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

        var pusb = PUSB.get_all_records(session).First();
        Console.WriteLine($"Device:         {pusb.Value.description}");

        // Passthrough is off until an administrator enables it on the device — a VUSB.create against a
        // device that has not been released fails rather than silently doing nothing.
        PUSB.set_passthrough_enabled(session, pusb.Key, true);

        var vusb = VUSB.create(session, vm.opaque_ref, pusb.Value.USB_group, new Dictionary<string, string>());
        Console.WriteLine($"Attached:       {VM.get_VUSBs(session, vm.opaque_ref).Count} device(s)");

        // VUSB.destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM
        // it gets plugged in as soon as it's created, so unplug it first.
        if (VUSB.get_currently_attached(session, vusb.opaque_ref)) VUSB.unplug(session, vusb.opaque_ref);
        VUSB.destroy(session, vusb.opaque_ref);
        PUSB.set_passthrough_enabled(session, pusb.Key, false);
        Console.WriteLine("OK: attach-usb-device");
        session.logout();
    }
}
