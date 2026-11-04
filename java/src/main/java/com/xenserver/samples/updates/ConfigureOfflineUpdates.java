package com.xenserver.samples.updates;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Repository;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.classic.methods.HttpPut;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.EntityUtils;
import org.apache.hc.core5.http.io.entity.FileEntity;

import java.io.File;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class ConfigureOfflineUpdates {
    private ConfigureOfflineUpdates() {
    }

    /**
     * Configure updates for an air-gapped pool.
     *
     * <p>Switch a pool with no internet access to offline updates: make an update bundle repository the
     * pool's only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it
     * makes available, then tidy up.
     *
     * <p>A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool
     * needs a repository of the bundle kind (it can have only one: Repository.introduce_bundle refuses a
     * second with BUNDLE_REPOSITORY_ALREADY_EXISTS, so use the existing one), and it must be the pool's only
     * enabled repository. Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a
     * task in the query string: the pool unpacks and checks the bundle, and the task says how that went. GET
     * /updates then lists what the bundle offers each host, and host.apply_updates applies it with the hash
     * in that list (see ApplyUpdate). With a null bundlePath this only switches the channel and back.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureOfflineUpdates.run("https://xenserver", "root", password, "XS9-update.xsbundle");
     * }</pre>
     */
    public static void run(String url, String user, String password, String bundlePath) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();

        // Remember the pool's own repositories, to put them back afterwards.
        Set<Repository> previous = pool.getRepositories(conn);
        Repository existing = null;
        for (Map.Entry<Repository, Repository.Record> e : Repository.getAllRecords(conn).entrySet())
            if (e.getValue().origin == Types.Origin.BUNDLE) existing = e.getKey();
        Repository repo = existing != null ? existing
            : Repository.introduceBundle(conn, "sdk-example-offline", "Updates from uploaded bundles");
        try {
            pool.setRepositories(conn, Set.of(repo));
            for (Repository r : pool.getRepositories(conn))
                System.out.println("Pool repositories: " + r.getNameLabel(conn));

            if (bundlePath != null && !bundlePath.isEmpty()) {
                String session = conn.getSessionReference();
                Task task = Task.create(conn, "sdk-example-bundle-upload", "");
                try {
                    HttpPut put = new HttpPut(url + "/bundle?session_id=" + session + "&task_id=" + task.toWireString());
                    put.setEntity(new FileEntity(new File(bundlePath), null));
                    try (CloseableHttpClient http = trustingHttpClient()) {
                        http.execute(put, response -> EntityUtils.toString(response.getEntity()));
                    }
                    while (task.getStatus(conn) == Types.TaskStatusType.PENDING) Thread.sleep(1000);
                    if (task.getStatus(conn) != Types.TaskStatusType.SUCCESS)
                        throw new RuntimeException("bundle upload failed: " + task.getErrorInfo(conn));
                } finally {
                    task.destroy(conn);
                }
                System.out.println("Uploaded " + new File(bundlePath).getName());

                String json;
                try (CloseableHttpClient http = trustingHttpClient()) {
                    json = http.execute(new HttpGet(url + "/updates?session_id=" + session),
                        response -> EntityUtils.toString(response.getEntity()));
                }
                JsonNode available = new ObjectMapper().readTree(json);
                System.out.printf("Updates in the bundle: %d (apply them with hash %s)%n",
                    available.path("updates").size(), available.path("hash").asText());
            } else {
                System.out.println("No bundle given: pass bundle_path to upload one");
            }
        } finally {
            // Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
            pool.setRepositories(conn, previous);
            if (existing == null) repo.forget(conn);
        }
        System.out.println("OK: configure-offline-updates");
        Session.logout(conn);
    }
}
