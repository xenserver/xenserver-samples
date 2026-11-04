using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by default,
    /// then put the original choice back.
    /// </summary>
    public static void SetDefaultSr(string url, string user, string password,
        string nfsServer = "192.0.2.10", string nfsPath = "/export/spare")
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session).First().opaque_ref;

        // Capture all three separately. New disks land on the default SR, a suspended VM's memory image
        // goes to the suspend-image SR and host crash dumps to the crash-dump SR. They are usually the
        // same storage but need not be, and a pool that has never suspended or crashed anything can
        // legitimately leave the latter two unset — so restoring all three from the default would
        // quietly invent settings that were not there.
        var before = Pool.get_default_SR(session, pool).opaque_ref;
        var beforeSuspend = Pool.get_suspend_image_SR(session, pool).opaque_ref;
        var beforeCrash = Pool.get_crash_dump_SR(session, pool).opaque_ref;
        Console.WriteLine($"default storage:  {SrLabel(session, before)}");
        Console.WriteLine($"  suspend images: {SrLabel(session, beforeSuspend)}");
        Console.WriteLine($"  crash dumps:    {SrLabel(session, beforeCrash)}");

        // Somewhere to switch to. A pool default has to be reachable from every host, so it is a shared
        // SR; a local one would strand any VM whose disk landed on the wrong host.
        var sr = SR.create(session, Host.get_all(session).First().opaque_ref,
            new Dictionary<string, string>
            {
                ["server"] = nfsServer,
                ["serverpath"] = nfsPath,
                ["nfsversion"] = "3",
            }, 0, "sdk-example-default", "SR used by the SDK default-storage example",
            "nfs", "user", true, new Dictionary<string, string>()).opaque_ref;

        Pool.set_default_SR(session, pool, sr);
        Pool.set_suspend_image_SR(session, pool, sr);
        Pool.set_crash_dump_SR(session, pool, sr);
        Console.WriteLine($"  switched to:    {SrLabel(session, Pool.get_default_SR(session, pool).opaque_ref)}");

        // Restore the original choice before tidying up: an SR that is still the pool default is the
        // awkward one to remove.
        Pool.set_default_SR(session, pool, before);
        Pool.set_suspend_image_SR(session, pool, beforeSuspend);
        Pool.set_crash_dump_SR(session, pool, beforeCrash);
        foreach (var pbd in SR.get_PBDs(session, sr)) PBD.unplug(session, pbd.opaque_ref);
        SR.forget(session, sr);
        Console.WriteLine($"  restored to:    {SrLabel(session, Pool.get_default_SR(session, pool).opaque_ref)}");
        Console.WriteLine("OK: set-default-sr");
        session.logout();
    }

    /// <summary>An SR's name, tolerating the null reference an unset pool field holds.</summary>
    private static string SrLabel(Session session, string sr) =>
        string.IsNullOrEmpty(sr) || sr == "OpaqueRef:NULL" ? "(none)" : SR.get_name_label(session, sr);
}
