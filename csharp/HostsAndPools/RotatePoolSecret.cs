using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Rotate the shared secret that authenticates pool members to each other.
    /// </summary>
    public static void RotatePoolSecret(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var poolRef = Pool.get_all_records(session).Keys.First().opaque_ref;
        Console.WriteLine($"Pool:           {Pool.get_name_label(session, poolRef)}");

        // xapi checks its own preconditions before rotating - HA must be disabled, every host must be
        // live, no rolling pool upgrade may be in progress, and the pool must be licensed for it - and
        // raises a clear error naming which one failed rather than silently refusing. Report that
        // explanation instead of letting an unhandled Failure speak for itself.
        var explanations = new Dictionary<string, string>
        {
            ["HA_IS_ENABLED"] = "HA is enabled on this pool; disable it first.",
            ["CANNOT_CONTACT_HOST"] = "a host in the pool is not reachable.",
            ["NOT_SUPPORTED_DURING_UPGRADE"] = "a rolling pool upgrade is in progress.",
            ["LICENCE_RESTRICTION"] = "this edition is not licensed for pool secret rotation.",
        };
        try
        {
            // A pool-wide operation; existing sessions survive it.
            Pool.rotate_secret(session);
            Console.WriteLine($"Rotated. Still connected: {Pool.get_all(session).Count == 1}");
        }
        catch (Failure f)
        {
            var explanation = explanations.TryGetValue(f.ErrorDescription[0], out var e) ? e : "see the error for detail";
            Console.WriteLine($"Could not rotate the pool secret: {f.ErrorDescription[0]} ({explanation})");
        }
        Console.WriteLine("OK: rotate-pool-secret");
        session.logout();
    }
}
