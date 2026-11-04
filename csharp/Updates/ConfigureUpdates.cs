using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Point the pool at a CDN update repository and turn on automatic update sync: register a repository,
    /// set it as the pool's repository, enable update sync, read it back, then tidy up.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureUpdates("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    /// Workflows."https://repo-src.ops.xenserver.com/xs9");
    /// </code>
    /// </example>
    public static void ConfigureUpdates(string url, string user, string password, string repoUrl, string sourceUrl)
    {
        var session = Connect(url, user, password);
        var repos = IntroduceUpdateRepositories(session, repoUrl, sourceUrl);
        Console.WriteLine("Introduced repositories: " +
            string.Join(", ", repos.Select(r => Repository.get_name_label(session, r.opaque_ref))));

        var pool = Pool.get_all(session)[0].opaque_ref;
        // Remember the pool's own repositories, to put them back afterwards.
        var previous = Pool.get_repositories(session, pool);
        Pool.set_repositories(session, pool, repos);
        Pool.set_update_sync_enabled(session, pool, true);
        Console.WriteLine($"Pool repositories: {Pool.get_repositories(session, pool).Count}; " +
            $"auto-sync enabled: {Pool.get_update_sync_enabled(session, pool)}");

        // Tidy up so the example is repeatable.
        Pool.set_update_sync_enabled(session, pool, false);
        Pool.set_repositories(session, pool, previous);
        foreach (var repo in repos) Repository.forget(session, repo.opaque_ref);
        Console.WriteLine("OK: configure-updates");
        session.logout();
    }
}
