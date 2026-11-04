using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Find the crash dumps a host kept after a failure, report how big and how old they are, then delete
    /// them to free the space.
    /// </summary>
    public static void ManageCrashDumps(string url, string user, string password)
    {
        var session = Connect(url, user, password);

        // When a host crashes it writes a dump to its local disk and keeps it. They are large, nothing
        // cleans them up, and a host that has crashed more than once accumulates them — so clearing them
        // once support has what it needs is ordinary housekeeping. They belong to the host that wrote
        // them, so clear them a host at a time.
        var host = Host.get_all(session)
            .FirstOrDefault(h => Host.get_crashdumps(session, h.opaque_ref).Count > 0)?.opaque_ref;
        if (host == null)
        {
            Console.WriteLine("No crash dumps in this pool — nothing to clear.");
            Console.WriteLine("OK: manage-crash-dumps");
            session.logout();
            return;
        }

        var dumps = Host.get_crashdumps(session, host);
        long total = 0;
        Console.WriteLine($"{Host.get_name_label(session, host)} has {dumps.Count} crash dump(s)");
        foreach (var dump in dumps)
        {
            var record = Host_crashdump.get_record(session, dump.opaque_ref);
            total += record.size;
            Console.WriteLine($"  {record.timestamp:yyyyMMdd'T'HH:mm:ss'Z'}  {Mib(record.size)}");
        }
        Console.WriteLine($"  {Mib(total)} in total");

        // Deleting a dump frees the space on the host; the host itself is untouched.
        foreach (var dump in dumps) Host_crashdump.destroy(session, dump.opaque_ref);
        Console.WriteLine($"  cleared:  {Host.get_name_label(session, host)} now has "
                          + Host.get_crashdumps(session, host).Count);

        Console.WriteLine("OK: manage-crash-dumps");
        session.logout();
    }

    private static string Mib(long size) => $"{size / (1024 * 1024)} MiB";
}
