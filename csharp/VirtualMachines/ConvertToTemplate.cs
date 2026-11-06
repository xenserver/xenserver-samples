using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Turn a VM into a reusable custom template. This is a one-way operation.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConvertToTemplate("https://xenserver", "root", password, "Rocky Linux 8");
    /// </code>
    /// </example>
    public static void ConvertToTemplate(string url, string user, string password,
        string templateName, string newVmName = "sdk-example-totemplate")
    {
        var session = Connect(url, user, password);
        var vm = VM.clone(session, TemplateByName(session, templateName), newVmName);
        Provision(session, vm); // now a real (halted) VM
        Console.WriteLine($"is_a_template after provision: {VM.get_is_a_template(session, vm)}");

        // Converting a VM to a custom template is a one-way operation.
        VM.set_is_a_template(session, vm, true);
        Console.WriteLine($"is_a_template after convert:  {VM.get_is_a_template(session, vm)}");

        DestroyVmAndDisks(session, vm);
        Console.WriteLine("OK: convert-to-template");
        session.logout();
    }
}
