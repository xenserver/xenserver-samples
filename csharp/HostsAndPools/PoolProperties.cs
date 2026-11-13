using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Read the pool name and default storage repository, then rename the pool and restore it.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.PoolProperties("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void PoolProperties(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var poolRef = Pool.get_all(session)[0];
        var original = Pool.get_name_label(session, poolRef);
        var defaultSr = Pool.get_default_SR(session, poolRef);
        Console.WriteLine($"Pool:       '{original}'");
        Console.WriteLine($"Default SR: {(Helper.IsNullOrEmptyOpaqueRef(defaultSr)
            ? "(none)" : SR.get_name_label(session, defaultSr))}");

        Pool.set_name_label(session, poolRef, "sdk-pool-renamed");
        Console.WriteLine($"Renamed to: '{Pool.get_name_label(session, poolRef)}'");
        Pool.set_name_label(session, poolRef, original); // restore
        Console.WriteLine("OK: pool-properties");
        session.logout();
    }
}
