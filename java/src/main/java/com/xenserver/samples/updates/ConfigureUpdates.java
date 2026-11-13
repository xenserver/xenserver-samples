package com.xenserver.samples.updates;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Repository;
import com.xensource.xenapi.Session;

import java.util.Set;

import static com.xenserver.samples.Helpers.introduceUpdateRepositories;
import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureUpdates {
    private ConfigureUpdates() {
    }

    /**
     * Configure updates (CDN).
     *
     * <p>Point the pool at a CDN update repository and turn on automatic update sync: register a
     * repository, set it as the pool's repository, enable update sync, read it back, then tidy up.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureUpdates.run("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
     * "https://repo-src.ops.xenserver.com/xs9");
     * }</pre>
     */
    public static void run(String url, String user, String password, String repoUrl,
            String sourceUrl) throws Exception {
        Connection conn = connect(url, user, password);
        Set<Repository> repos = introduceUpdateRepositories(conn, repoUrl, sourceUrl);
        StringBuilder names = new StringBuilder();
        for (Repository repo : repos) {
            if (names.length() > 0) names.append(", ");
            names.append(repo.getNameLabel(conn));
        }
        System.out.println("Introduced repositories: " + names);

        Pool pool = Pool.getAll(conn).iterator().next();
        // Remember the pool's own repositories, to put them back afterwards.
        Set<Repository> previous = pool.getRepositories(conn);
        pool.setRepositories(conn, repos);
        pool.setUpdateSyncEnabled(conn, true);
        System.out.println("Pool repositories: " + pool.getRepositories(conn).size()
                + "; auto-sync enabled: " + pool.getUpdateSyncEnabled(conn));

        // Tidy up so the example is repeatable.
        pool.setUpdateSyncEnabled(conn, false);
        pool.setRepositories(conn, previous);
        for (Repository repo : repos) repo.forget(conn);
        System.out.println("OK: configure-updates");
        Session.logout(conn);
    }
}
