using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Clone one of the built-in templates and provision the clone into a real, installable VM.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CreateVm("https://xenserver", "root", password, "Rocky Linux 8");
    /// </code>
    /// </example>
    public static void CreateVm(string url, string user, string password,
        string templateName, string newVmName = "sdk-example-vm")
    {
        var session = Connect(url, user, password);
        var templateRef = TemplateByName(session, templateName);
        Console.WriteLine($"Using template: {VM.get_name_label(session, templateRef)}");

        var vmRef = VM.clone(session, templateRef, newVmName);
        Console.WriteLine($"Cloned new VM: {VM.get_uuid(session, vmRef)}");

        Provision(session, vmRef);
        Console.WriteLine($"Provisioned. is_a_template = {VM.get_is_a_template(session, vmRef)}");

        DestroyVmAndDisks(session, vmRef);
        Console.WriteLine("Cleaned up the example VM.");

        Console.WriteLine("OK: create-vm");
        session.logout();
    }
}
