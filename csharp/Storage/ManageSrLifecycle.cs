using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Take a storage repository offline and bring it back: disconnect it from every host, reconnect and
    /// rescan it, then disconnect it once more and forget it for good.
    /// </summary>
    public static void ManageSrLifecycle(string url, string user, string password,
        string nfsServer = "192.0.2.10", string nfsPath = "/export/spare")
    {
        var session = Connect(url, user, password);

        // There is no "detach" call on an SR. A shared SR is joined to each host by one PBD — a physical
        // block device — and detaching the SR means unplugging every one of them. That is why an SR can
        // be attached on some hosts and not others, and why a repair action exists at all: it plugs back
        // the PBDs that are missing.
        var host = Host.get_all(session).First().opaque_ref;
        var sr = SR.create(session, host, new Dictionary<string, string>
        {
            ["server"] = nfsServer,
            ["serverpath"] = nfsPath,
            ["nfsversion"] = "3",
        }, 0, "sdk-example-lifecycle", "SR used by the SDK lifecycle example",
            "nfs", "user", true, new Dictionary<string, string>()).opaque_ref;

        var pbds = SR.get_PBDs(session, sr).Select(p => p.opaque_ref).ToList();
        Console.WriteLine($"{SR.get_name_label(session, sr)}: connected on "
                          + $"{AttachedPbds(session, pbds)} of {pbds.Count} host(s)");

        foreach (var pbd in pbds) PBD.unplug(session, pbd);
        Console.WriteLine($"  detached:   connected on {AttachedPbds(session, pbds)} host(s)");

        // Plugging them back is exactly what a repair does.
        foreach (var pbd in pbds) PBD.plug(session, pbd);
        Console.WriteLine($"  reattached: connected on {AttachedPbds(session, pbds)} host(s)");

        SR.scan(session, sr);
        Console.WriteLine($"  rescanned:  {SR.get_VDIs(session, sr).Count} disk(s)");

        // Forgetting drops the pool's record of the SR but leaves the storage itself untouched, so the
        // same export can be introduced again later. Detach before forgetting: a connected SR is in use.
        foreach (var pbd in pbds) PBD.unplug(session, pbd);
        SR.forget(session, sr);
        Console.WriteLine("  forgotten");
        Console.WriteLine("OK: manage-sr-lifecycle");
        session.logout();
    }

    /// <summary>How many of these connections are currently live.</summary>
    private static int AttachedPbds(Session session, IEnumerable<string> pbds) =>
        pbds.Count(pbd => PBD.get_currently_attached(session, pbd));
}
