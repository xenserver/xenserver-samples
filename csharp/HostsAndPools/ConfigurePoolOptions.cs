using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and
    /// memory-migration compression — then put them back.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigurePoolOptions("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ConfigurePoolOptions(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session)[0].opaque_ref;

        // None of these is a wizard: they are plain pool settings that a client exposes on a
        // properties page, and each is a single field. Read them, change them, put them back.
        var livePatchingDisabled = Pool.get_live_patching_disabled(session, pool);
        var igmpSnooping = Pool.get_igmp_snooping_enabled(session, pool);
        var migrationCompression = Pool.get_migration_compression(session, pool);
        Console.WriteLine($"  {"live patching disabled",-22} {livePatchingDisabled}");
        Console.WriteLine($"  {"IGMP snooping",-22} {igmpSnooping}");
        Console.WriteLine($"  {"migration compression",-22} {migrationCompression}");

        // Live patching applies host updates without a reboot; disabling it forces the reboot.
        Pool.set_live_patching_disabled(session, pool, !livePatchingDisabled);
        // IGMP snooping keeps multicast off ports that did not ask for it.
        Pool.set_igmp_snooping_enabled(session, pool, !igmpSnooping);
        // Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
        Pool.set_migration_compression(session, pool, !migrationCompression);

        Console.WriteLine("after changing:");
        Console.WriteLine($"  {"live patching disabled",-22} {Pool.get_live_patching_disabled(session, pool)}");
        Console.WriteLine($"  {"IGMP snooping",-22} {Pool.get_igmp_snooping_enabled(session, pool)}");
        Console.WriteLine($"  {"migration compression",-22} {Pool.get_migration_compression(session, pool)}");

        Pool.set_live_patching_disabled(session, pool, livePatchingDisabled);
        Pool.set_igmp_snooping_enabled(session, pool, igmpSnooping);
        Pool.set_migration_compression(session, pool, migrationCompression);
        Console.WriteLine("  restored");
        Console.WriteLine("OK: configure-pool-options");
        session.logout();
    }
}
