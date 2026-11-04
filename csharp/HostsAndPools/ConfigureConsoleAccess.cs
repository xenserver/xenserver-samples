using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles and
    /// for VM consoles, one session at a time, and refusing plain HTTP.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureConsoleAccess("https://xenserver", "root", password);
    /// </code>
    /// </example>
    /// <remarks>
    /// <para>
    /// Tighten how consoles and management traffic may be used. Idle console sessions are set at two levels —
    /// the pool's own management consoles and the VM consoles it serves — and a host can override the pool's.
    /// Requiring HTTPS refuses plain HTTP to the management interface altogether.
    /// </para>
    /// <para>
    /// NOTE: SDK 26.14's C# binding has Pool.set_console_idle_timeout and Pool.set_https_only but no matching
    /// GETTERS (unlike host.console_idle_timeout, which has both) — so the pool's own management-console
    /// timeout and its HTTPS-only flag can be set here but not read back through this binding. Those two read
    /// lines are therefore omitted rather than worked around.
    /// </para>
    /// </remarks>
    public static void ConfigureConsoleAccess(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session)[0].opaque_ref;
        var host = Pool.get_master(session, pool).opaque_ref;

        Console.WriteLine($"  {"VM console idle timeout",-26} {Pool.get_vm_console_idle_timeout(session, pool)}s");
        Console.WriteLine($"  {"limit console sessions",-26} {Pool.get_limit_console_sessions(session, pool)}");
        Console.WriteLine($"  {"host console idle timeout",-26} {Host.get_console_idle_timeout(session, host)}s");

        // Ten minutes of inactivity, one console session at a time, and no plain HTTP.
        Pool.set_console_idle_timeout(session, pool, 600);
        Pool.set_vm_console_idle_timeout(session, pool, 600);
        Pool.set_limit_console_sessions(session, pool, true);
        Host.set_console_idle_timeout(session, host, 300);
        Pool.set_https_only(session, pool, true);

        Console.WriteLine("after tightening:");
        Console.WriteLine($"  {"VM console idle timeout",-26} {Pool.get_vm_console_idle_timeout(session, pool)}s");
        Console.WriteLine($"  {"limit console sessions",-26} {Pool.get_limit_console_sessions(session, pool)}");
        Console.WriteLine($"  {"host console idle timeout",-26} {Host.get_console_idle_timeout(session, host)}s");

        Pool.set_https_only(session, pool, false);
        Pool.set_console_idle_timeout(session, pool, 0);
        Pool.set_vm_console_idle_timeout(session, pool, 0);
        Pool.set_limit_console_sessions(session, pool, false);
        Host.set_console_idle_timeout(session, host, 0);
        Console.WriteLine("  restored");
        Console.WriteLine("OK: configure-console-access");
        session.logout();
    }
}
