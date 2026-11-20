using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Change a VM's description and custom metadata, then read the changes back.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.EditVmProperties("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void EditVmProperties(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);
        var vmRef = VmByName(session, vmName);

        var originalDesc = VM.get_name_description(session, vmRef);
        VM.set_name_description(session, vmRef, "Edited by the SDK example");
        VM.add_to_other_config(session, vmRef, "sdk_example", "true");
        Console.WriteLine($"New description: {VM.get_name_description(session, vmRef)}");
        Console.WriteLine($"other_config[sdk_example] = {VM.get_other_config(session, vmRef)["sdk_example"]}");

        VM.set_name_description(session, vmRef, originalDesc);
        VM.remove_from_other_config(session, vmRef, "sdk_example");
        Console.WriteLine("OK: edit-vm-properties");
        session.logout();
    }
}
