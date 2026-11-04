using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Resolve a stable UUID back to a live object reference — how to persist a reference to an object across
    /// sessions.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.FindByUuid("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void FindByUuid(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);
        // UUIDs are stable identifiers you can persist and resolve back to a (session-scoped) ref.
        var vm = VmByName(session, vmName);
        var uuid = VM.get_uuid(session, vm);
        var resolved = VM.get_by_uuid(session, uuid).opaque_ref;
        Console.WriteLine($"UUID {uuid} resolves to {VM.get_name_label(session, resolved)}");
        Console.WriteLine($"Same object: {resolved == vm}");
        Console.WriteLine("OK: find-by-uuid");
        session.logout();
    }
}
