using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and hosts.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.PoolTags("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void PoolTags(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var poolRef = Pool.get_all(session)[0].opaque_ref;
        Pool.add_tags(session, poolRef, "sdk-managed");
        Console.WriteLine($"Pool tags: {string.Join(", ", Pool.get_tags(session, poolRef))}");
        Pool.remove_tags(session, poolRef, "sdk-managed");
        Console.WriteLine("OK: pool-tags");
        session.logout();
    }
}
