using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type),
    /// place the VM in a folder, read it all back, then tidy up.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.TagsAndFolders("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void TagsAndFolders(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);
        var vm = VmByName(session, vmName);
        var host = Host.get_all(session)[0];

        // Tags work on any object type (VM, host, SR, network, …).
        VM.add_tags(session, vm, "web");
        Host.add_tags(session, host, "gold");
        Console.WriteLine($"VM tags:   {string.Join(", ", VM.get_tags(session, vm))}");
        Console.WriteLine($"Host tags: {string.Join(", ", Host.get_tags(session, host))}");

        // Folder placement lives in other_config["folder"] as a leading-slash path.
        VM.add_to_other_config(session, vm, "folder", "/Production/Web");
        Console.WriteLine($"VM folder: {VM.get_other_config(session, vm)["folder"]}");

        VM.remove_tags(session, vm, "web");
        Host.remove_tags(session, host, "gold");
        VM.remove_from_other_config(session, vm, "folder");
        Console.WriteLine("OK: tags-and-folders");
        session.logout();
    }
}
