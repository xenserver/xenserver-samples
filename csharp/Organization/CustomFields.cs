using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the
    /// object.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CustomFields("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void CustomFields(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);
        // XenCenter's custom fields are stored in other_config under "XenCenter.CustomFields.<name>".
        var vm = VmByName(session, vmName);
        const string key = "XenCenter.CustomFields.Owner";
        VM.add_to_other_config(session, vm, key, "Platform Team");
        Console.WriteLine($"Custom field Owner = {VM.get_other_config(session, vm)[key]}");

        VM.remove_from_other_config(session, vm, key);
        Console.WriteLine("OK: custom-fields");
        session.logout();
    }
}
