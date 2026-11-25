package com.xenserver.samples.updates;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
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
import java.util.List;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.checkHaAndWlbOff;
import static com.xenserver.samples.Helpers.checkHostsCanBeEvacuated;
import static com.xenserver.samples.Helpers.checkNoPendingGuidance;
import static com.xenserver.samples.Helpers.hostsCoordinatorFirst;
import static com.xenserver.samples.Helpers.reportVmGuidance;
import static com.xenserver.samples.Helpers.updateHosts;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class OfflinePoolUpdate {
    private OfflinePoolUpdate() {
    }

    /**
     * Update an air-gapped pool from a bundle.
     *
     * <p>Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make
     * a bundle repository the pool's update repository, upload the bundle, list the updates it offers, then
     * apply them host by host - coordinator first, moving each host's VMs to the rest of the pool - so the
     * VMs keep running throughout.
     *
     * <p>Check first, before changing anything, that the update can go through: HA and Workload Balancing
     * off, no host or VM with mandatory guidance still pending from an earlier update, and every host able
     * to empty. Then make a repository of the bundle kind the pool's only enabled repository - a pool can
     * have only one (Repository.introduceBundle refuses a second with BUNDLE_REPOSITORY_ALREADY_EXISTS), so
     * use the existing one if there is one.
     *
     * <p>Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a task in the query
     * string. The server answers 200 before it has read the bundle, so the task says how it went: the pool
     * unpacks the bundle, checks its signature and syncs its updates before the task completes. GET
     * /updates then lists what the bundle offers and the hash to apply it with, and Helpers.updateHosts
     * applies it to each host in turn as RollingPoolUpdate does. Finally report the guidance left for VMs,
     * such as restarting one to pick the update up - that is the VM owner's call.
     *
     * <p>A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts the
     * pool's previous repositories back afterwards so that it can run again on a test pool.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * OfflinePoolUpdate.run("https://xenserver", "root", password, "XS9-update.xsbundle");
     * }</pre>
     */
    public static void run(String url, String user, String password, String bundlePath) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        List<Host> hosts = hostsCoordinatorFirst(conn);
        checkHaAndWlbOff(conn, pool);
        checkNoPendingGuidance(conn);
        checkHostsCanBeEvacuated(conn, hosts);

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
                    throw new IllegalStateException("bundle upload failed: " + task.getErrorInfo(conn));
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
            JsonNode updates = available.path("updates");
            System.out.println("Updates in the bundle: " + updates.size());
            for (JsonNode update : updates)
                System.out.println("  " + update.path("id").asText() + ": " + update.path("summary").asText());
            if (!updates.isEmpty())
                conn = updateHosts(conn, url, user, password, hosts, available.path("hash").asText());
        } finally {
            // Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
            pool.setRepositories(conn, previous);
            if (existing == null) repo.forget(conn);
        }
        reportVmGuidance(conn);
        System.out.println("OK: offline-pool-update");
        Session.logout(conn);
    }
}
