using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Catch an API failure and inspect its error code and parameters — the shape of every error the API
    /// returns, and how to react to it robustly.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ErrorHandling("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ErrorHandling(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        // XenAPI errors surface as a Failure whose ErrorDescription is [CODE, param1, param2, ...].
        try
        {
            Host.get_by_uuid(session, "this-uuid-does-not-exist");
            Console.WriteLine("unexpected: no error");
        }
        catch (Failure f)
        {
            Console.WriteLine($"Caught expected failure: {f.ErrorDescription[0]}");
            // Failure.Message (ShortMessage is obsolete and returns the same text).
            Console.WriteLine($"Short message: {f.Message}");
        }
        Console.WriteLine("OK: error-handling");
        session.logout();
    }
}
