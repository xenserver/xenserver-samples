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
    /// Switch a pool with no internet access to offline updates: make an update bundle repository the pool's
    /// only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it makes
    /// available, then tidy up.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureOfflineUpdates("https://xenserver", "root", password, "XS9-update.xsbundle");
    /// </code>
    /// </example>
    /// <remarks>
    /// A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool needs
    /// a repository of the bundle kind (it can have only one: Repository.introduce_bundle refuses a second
    /// with BUNDLE_REPOSITORY_ALREADY_EXISTS, so use the existing one), and it must be the pool's only enabled
    /// repository. Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a task in
    /// the query string: the pool unpacks and checks the bundle, and the task says how that went. GET
    /// /updates then lists what the bundle offers each host, and host.apply_updates applies it with the hash
    /// in that list (see ApplyUpdate). Without bundlePath this only switches the channel and back.
    /// </remarks>
    public static void ConfigureOfflineUpdates(string url, string user, string password, string bundlePath = null)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session)[0];

        // Remember the pool's own repositories, to put them back afterwards.
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

            if (!string.IsNullOrEmpty(bundlePath))
            {
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
                        throw new Exception("bundle upload failed: " +
                                            string.Join(", ", Task.get_error_info(session, task)));
                }
                finally
                {
                    Task.destroy(session, task);
                }
                Console.WriteLine($"Uploaded {Path.GetFileName(bundlePath)}");

                using (var client = InsecureHttpClient())
                using (var available = JsonDocument.Parse(
                           client.GetStringAsync($"{url}/updates?session_id={session.opaque_ref}").Result))
                {
                    var root = available.RootElement;
                    var count = root.TryGetProperty("updates", out var updates) ? updates.GetArrayLength() : 0;
                    var hash = root.TryGetProperty("hash", out var h) ? h.GetString() : "";
                    Console.WriteLine($"Updates in the bundle: {count} (apply them with hash {hash})");
                }
            }
            else
            {
                Console.WriteLine("No bundle given: pass bundle_path to upload one");
            }
        }
        finally
        {
            // Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
            Pool.set_repositories(session, pool, previous);
            if (existing == null) Repository.forget(session, repo);
        }
        Console.WriteLine("OK: configure-offline-updates");
        session.logout();
    }
}
