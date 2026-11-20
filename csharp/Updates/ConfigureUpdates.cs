using System.Collections.Generic;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Point the pool at a CDN update repository and turn on automatic update sync: register the repository,
    /// set it as the pool's repository, enable update sync, read it back, then tidy up.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureUpdates("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    ///     "https://repo-src.ops.xenserver.com/xs9");
    /// </code>
    /// </example>
    public static void ConfigureUpdates(string url, string user, string password, string repoUrl, string sourceUrl)
    {
        var session = Connect(url, user, password);
        var repo = IntroduceUpdateRepository(session, repoUrl, sourceUrl);
        Console.WriteLine($"Introduced repository: {Repository.get_name_label(session, repo)}");

        var pool = Pool.get_all(session)[0];
        // Remember the pool's own repositories, to put them back afterwards.
        var previous = Pool.get_repositories(session, pool);
        Pool.set_repositories(session, pool, new List<XenRef<Repository>> { repo });
        Pool.set_update_sync_enabled(session, pool, true);
        Console.WriteLine($"Pool repositories: {Pool.get_repositories(session, pool).Count}; " +
            $"auto-sync enabled: {Pool.get_update_sync_enabled(session, pool)}");

        // Tidy up so the example is repeatable.
        Pool.set_update_sync_enabled(session, pool, false);
        Pool.set_repositories(session, pool, previous);
        Repository.forget(session, repo);
        Console.WriteLine("OK: configure-updates");
        session.logout();
    }
}
