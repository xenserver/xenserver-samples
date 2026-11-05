using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Enable the clustering layer that shared block storage needs for thin provisioning, then watch quorum
    /// as a host leaves the cluster and rejoins it.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureClustering("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ConfigureClustering(string url, string user, string password)
    {
        var session = Connect(url, user, password);

        // Clustering is what shared block storage needs before it can be thin-provisioned with GFS2. Run
        // it over a network every host is on - the management network - since corosync is
        // latency-sensitive and a cluster that loses quorum takes its GFS2 storage offline with it.
        var pifs = PIF.get_all_records(session);
        var network = pifs.First(kv => kv.Value.management).Value.network.opaque_ref;
        var was = pifs.Where(kv => kv.Value.network.opaque_ref == network)
            .ToDictionary(kv => kv.Key.opaque_ref, kv => kv.Value.disallow_unplug);

        var existing = Cluster.get_all(session);
        string cluster;
        if (existing.Count > 0)
            cluster = existing[0].opaque_ref;
        else
        {
            // Corosync must not lose its network, so each host's PIF on it has to refuse unplugging
            // first: Cluster.pool_create fails PIF_ALLOWS_UNPLUG otherwise. was remembers the settings.
            foreach (var pif in was.Keys)
                PIF.set_disallow_unplug(session, pif, true);
            // token_timeout is in seconds (the API's default is 20.0, coefficient 1.0): XS9 refuses 20000
            // as "too large" - it is not milliseconds.
            cluster = Cluster.pool_create(session, network, "corosync", 20.0, 1.0).opaque_ref;
        }

        var record = Cluster.get_record(session, cluster);
        Console.WriteLine($"Stack:      {record.cluster_stack}");
        Console.WriteLine($"Quorate:    {record.is_quorate} ({record.live_hosts}/{record.quorum} needed)");

        // Taking a host out is what a management-interface change does; it can cost the pool quorum,
        // which is why the field is worth reading back rather than assuming.
        var member = Cluster_host.get_all(session)[0].opaque_ref;
        Cluster_host.disable(session, member);
        Console.WriteLine($"One member out, quorate: {Cluster.get_is_quorate(session, cluster)}");

        Cluster_host.enable(session, member);
        Cluster.pool_resync(session, cluster);
        Console.WriteLine($"Resynced,   quorate: {Cluster.get_is_quorate(session, cluster)}");

        // Tidy up a cluster this example created (one that was already there stays), and the PIF settings.
        if (existing.Count == 0)
        {
            Cluster.pool_destroy(session, cluster);
            foreach (var (pif, value) in was)
                PIF.set_disallow_unplug(session, pif, value);
            Console.WriteLine("Cluster removed again.");
        }

        Console.WriteLine("OK: configure-clustering");
        session.logout();
    }
}
