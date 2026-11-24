using System;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make a
    /// bundle repository the pool's update repository, upload the bundle, list the updates it offers, then
    /// apply them host by host - coordinator first, moving each host's VMs to the rest of the pool - so the
    /// VMs keep running throughout.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.OfflinePoolUpdate("https://xenserver", "root", password, "XS9-update.xsbundle");
    /// </code>
    /// </example>
    /// <remarks>
    /// Check first, before changing anything, that the update can go through: HA and Workload Balancing off,
    /// no host or VM with mandatory guidance still pending from an earlier update, and every host able to
    /// empty. Then make a repository of the bundle kind the pool's only enabled repository - a pool can have
    /// only one (Repository.introduce_bundle refuses a second with BUNDLE_REPOSITORY_ALREADY_EXISTS), so use
    /// the existing one if there is one.
    ///
    /// Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a task in the query
    /// string. The server answers 200 before it has read the bundle, so the task says how it went: the pool
    /// unpacks the bundle, checks its signature and syncs its updates before the task completes. GET /updates
    /// then lists what the bundle offers and the hash to apply it with, and UpdateHosts applies it to each
    /// host in turn as rolling-pool-update does. Finally report the guidance left for VMs, such as
    /// restarting one to pick the update up - that is the VM owner's call.
    ///
    /// A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts the
    /// pool's previous repositories back afterwards so that it can run again on a test pool.
    /// </remarks>
    public static void OfflinePoolUpdate(string url, string user, string password, string bundlePath)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session)[0];
        var hosts = HostsCoordinatorFirst(session);
        CheckHaAndWlbOff(session, pool);
        CheckNoPendingGuidance(session);
        CheckHostsCanBeEvacuated(session, hosts);

        var previous = Pool.get_repositories(session, pool);
        var existing = Repository.get_all_records(session)
            .Where(kv => kv.Value.origin == origin.bundle).Select(kv => kv.Key).FirstOrDefault();
        var repo = existing ?? Repository.introduce_bundle(session, "sdk-example-offline",
            "Updates from uploaded bundles");
        try
        {
            Pool.set_repositories(session, pool, new() { repo });
            Console.WriteLine("Pool repositories: " + string.Join(", ",
                Pool.get_repositories(session, pool).Select(r => Repository.get_name_label(session, r))));

            var task = Task.create(session, "sdk-example-bundle-upload", "").opaque_ref;
            try
            {
                using var client = InsecureHttpClient();
                using var file = File.OpenRead(bundlePath);
                client.PutAsync($"{url}/bundle?session_id={session.opaque_ref}&task_id={task}",
                    new StreamContent(file)).Result.EnsureSuccessStatusCode();
                while (Task.get_status(session, task) == task_status_type.pending)
                    System.Threading.Thread.Sleep(1000);
                if (Task.get_status(session, task) != task_status_type.success)
                    throw new InvalidOperationException("bundle upload failed: " +
                                        string.Join(", ", Task.get_error_info(session, task)));
            }
            finally
            {
                Task.destroy(session, task);
            }
            Console.WriteLine($"Uploaded {Path.GetFileName(bundlePath)}");

            string hash;
            int count;
            using (var client = InsecureHttpClient())
            using (var available = JsonDocument.Parse(
                       client.GetStringAsync($"{url}/updates?session_id={session.opaque_ref}").Result))
            {
                var root = available.RootElement;
                var updates = root.GetProperty("updates");
                count = updates.GetArrayLength();
                hash = root.GetProperty("hash").GetString();
                Console.WriteLine($"Updates in the bundle: {count}");
                foreach (var update in updates.EnumerateArray())
                    Console.WriteLine($"  {update.GetProperty("id").GetString()}: {update.GetProperty("summary").GetString()}");
            }
            if (count > 0)
                session = UpdateHosts(session, url, user, password, hosts, hash);
        }
        finally
        {
            // Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
            Pool.set_repositories(session, pool, previous);
            if (existing == null) Repository.forget(session, repo);
        }
        ReportVmGuidance(session);
        Console.WriteLine("OK: offline-pool-update");
        session.logout();
    }
}
