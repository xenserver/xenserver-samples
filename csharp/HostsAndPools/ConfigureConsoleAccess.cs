using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles and
    /// for VM consoles, one session at a time, and refusing plain HTTP. Restore every value it changed
    /// afterwards.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureConsoleAccess("https://xenserver", "root", password);
    /// </code>
    /// </example>
    /// <remarks>
    /// <para>
    /// Tighten how consoles and management traffic may be used, then put back whatever was there before.
    /// Idle console sessions are set at two levels — the pool's own management consoles and the VM consoles
    /// it serves — and a host can override the pool's. Requiring HTTPS refuses plain HTTP to the management
    /// interface altogether.
    /// </para>
    /// <para>
    /// NOTE: Pool.set_console_idle_timeout and Pool.set_https_only are set below but never read back AT THE
    /// POOL LEVEL. SDK 26.14 generates a setter and no getter for either there, because both are really
    /// fan-outs that call the equivalent Host.set_* on every host rather than pool fields of their own.
    /// Host.https_only and Host.console_idle_timeout ARE ordinary readable fields, so this host's values are
    /// read back through them instead, to show the effect and to know what to restore.
    /// </para>
    /// </remarks>
    public static void ConfigureConsoleAccess(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session)[0];
        var host = Pool.get_master(session, pool);

        var beforeVmConsoleIdleTimeout = Pool.get_vm_console_idle_timeout(session, pool);
        var beforeLimitConsoleSessions = Pool.get_limit_console_sessions(session, pool);
        var beforeHostConsoleIdleTimeout = Host.get_console_idle_timeout(session, host);
        var beforeHostHttpsOnly = Host.get_https_only(session, host);
        Console.WriteLine($"  {"VM console idle timeout",-26} {beforeVmConsoleIdleTimeout}s");
        Console.WriteLine($"  {"limit console sessions",-26} {beforeLimitConsoleSessions}");
        Console.WriteLine($"  {"host console idle timeout",-26} {beforeHostConsoleIdleTimeout}s");
        Console.WriteLine($"  {"host https only",-26} {beforeHostHttpsOnly}");

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
        Console.WriteLine($"  {"host https only",-26} {Host.get_https_only(session, host)}");

        Pool.set_https_only(session, pool, beforeHostHttpsOnly);
        Pool.set_console_idle_timeout(session, pool, beforeHostConsoleIdleTimeout);
        Pool.set_vm_console_idle_timeout(session, pool, beforeVmConsoleIdleTimeout);
        Pool.set_limit_console_sessions(session, pool, beforeLimitConsoleSessions);
        Host.set_console_idle_timeout(session, host, beforeHostConsoleIdleTimeout);
        Console.WriteLine("  restored");
        Console.WriteLine("OK: configure-console-access");
        session.logout();
    }
}
