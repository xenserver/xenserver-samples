using System.Diagnostics;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part
    /// of your application's distributed trace.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.TraceApiCalls("https://xenserver", "root", password);
    /// </code>
    /// </example>
    /// <remarks>
    /// The SDK sends the current <see cref="Activity"/> to the pool as a W3C traceparent header with every
    /// call. In an application instrumented with OpenTelemetry, the request you are serving is already the
    /// current activity, so its trace carries on into the pool with no extra code; this example starts an
    /// activity of its own instead. The SDK's builds for .NET 8 and later also record each call as an
    /// activity, "XenAPI/&lt;method&gt;": add its source to your tracer (<c>.AddSource("XenServer.*")</c>)
    /// to export those too.
    /// </remarks>
    public static void TraceApiCalls(string url, string user, string password)
    {
        // Recorded: the trace is sampled, which the traceparent's flags tell the pool.
        using var trace = new Activity("trace-api-calls") { ActivityTraceFlags = ActivityTraceFlags.Recorded }
            .SetIdFormat(ActivityIdFormat.W3C).Start();
        Console.WriteLine($"Trace {trace.TraceId}: each call sends traceparent: {trace.Id}");

        var session = Connect(url, user, password);
        var hosts = Host.get_all(session);
        Console.WriteLine($"The pool has {hosts.Count} hosts");
        Console.WriteLine("OK: trace-api-calls");
        session.logout();
    }
}
