using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Change an object's name and read it back — how any object is renamed.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.RenameObject("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void RenameObject(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);
        var vm = VmByName(session, vmName);
        var original = VM.get_name_label(session, vm);
        VM.set_name_label(session, vm, "sdk-renamed");
        Console.WriteLine($"Renamed '{original}' → '{VM.get_name_label(session, vm)}'");
        VM.set_name_label(session, vm, original); // restore so the example is repeatable
        Console.WriteLine("OK: rename-object");
        session.logout();
    }
}
