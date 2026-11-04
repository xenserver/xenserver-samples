using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a
    /// client's view of the pool live.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.Events("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void Events(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);
        var classes = new[] { "VM" };
        var batch = (EventBatch)Event.from(session, classes, "", 1.0);
        var token = batch.token;
        Console.WriteLine("Established event token after initial snapshot.");

        var vmRef = VmByName(session, vmName);
        var original = VM.get_name_description(session, vmRef);
        VM.set_name_description(session, vmRef, "changed-to-trigger-event");

        batch = (EventBatch)Event.from(session, classes, token, 5.0);
        Console.WriteLine($"Received {batch.events.Length} event(s) after the change.");
        foreach (var ev in batch.events.Take(3))
            Console.WriteLine($"  - {ev.operation} {ev.class_}");

        VM.set_name_description(session, vmRef, original); // put it back
        Console.WriteLine("OK: events");
        session.logout();
    }
}
