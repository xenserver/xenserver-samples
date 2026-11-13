using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Start a long-running operation asynchronously to get a task back immediately, then poll it to
    /// completion and read its result — how to drive operations without blocking.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.WaitForTask("https://xenserver", "root", password, "Rocky Linux 8");
    /// </code>
    /// </example>
    public static void WaitForTask(string url, string user, string password,
        string templateName, string newVmName = "sdk-example-asynctask")
    {
        var session = Connect(url, user, password);
        // Every message has an Async.* twin that returns a Task ref immediately; poll it to completion.
        var task = VM.async_clone(session, TemplateByName(session, templateName), newVmName);
        Console.WriteLine($"Started task: {Task.get_uuid(session, task)}");

        while (Task.get_status(session, task) == task_status_type.pending)
        {
            Console.WriteLine($"  progress: {Task.get_progress(session, task):P0}");
            System.Threading.Thread.Sleep(200);
        }
        Console.WriteLine($"Task status: {Task.get_status(session, task)}");

        // The result of an object-creating task is <value>OpaqueRef:...</value>.
        var result = Task.get_result(session, task);
        var vmRef = result.Replace("<value>", "").Replace("</value>", "").Trim();
        Console.WriteLine($"Task produced VM: {VM.get_name_label(session, vmRef)}");

        // Tidy up.
        VM.destroy(session, vmRef);
        Task.destroy(session, task);
        Console.WriteLine("OK: wait-for-task");
        session.logout();
    }
}
