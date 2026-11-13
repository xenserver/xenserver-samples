package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.JsonRpcClient;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.classic.methods.HttpPut;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.EntityUtils;

import java.net.URL;

import static com.xenserver.samples.Helpers.hostUrl;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class BackupHostConfig {
    private BackupHostConfig() {
    }

    /**
     * Back up a host's configuration.
     *
     * <p>Download a host's configuration backup and verify it downloaded; optionally stage it back onto
     * that same host's backup partition, ready for a restore done from the installer.
     *
     * <p>Both /host_backup and /host_restore are served only by whichever host physically accepted the
     * HTTP connection - the handler ignores any ref= in the query string entirely, there is no forwarding
     * to another pool member. So backing up/restoring a host means opening the connection to THAT host's
     * own address, not to the pool's (coordinator) url. ref= is kept in the query string purely for
     * log-readability (a real host ignores it).
     *
     * <p>restore=true stages the backup onto the SAME host's backup partition. host-restore does not
     * restore the host there and then: it only writes the archive over that host's currently inactive
     * backup partition, ready for the next boot. It takes effect only once that host is booted from the
     * installer and Restore is chosen there.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * BackupHostConfig.run("https://xenserver", "root", password, false);
     * }</pre>
     */
    public static void run(String url, String user, String password, boolean restore) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
            Host host = com.xensource.xenapi.Pool.getAll(conn).iterator().next().getMaster(conn);
            String session = conn.getSessionReference();
            String hostUrl = hostUrl(url, host.getAddress(conn));
            System.out.println("Backing up " + host.getNameLabel(conn));

            // Backup and restore are HTTP transfers alongside the API, not API calls, so the session id
            // travels in the query string.
            java.io.File file = java.io.File.createTempFile("sdk-example-host", ".backup");
            HttpGet get = new HttpGet(hostUrl + "/host_backup?session_id=" + session
                    + "&ref=" + host.toWireString());
            // Hundreds of MB: stream it to disk rather than holding the whole backup in memory.
            try (CloseableHttpClient http = trustingHttpClient()) {
                http.execute(get, resp -> {
                    try (java.io.InputStream in = resp.getEntity().getContent()) {
                        java.nio.file.Files.copy(in, file.toPath(),
                                java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    }
                    return null;
                });
            }
            if (file.length() == 0) throw new IllegalStateException(file + " came back empty");
            System.out.printf("  wrote %d bytes to %s%n", file.length(), file.getName());
            // The connection's one keep-alive HTTP connection sat idle for as long as the download
            // took; a network that silently dropped it meanwhile would otherwise leave the next call
            // (Task.create below) hanging until the socket times out, so get a fresh one for the same
            // session before making another API call.
            conn = dropIdleConnection(conn, url);

            String name = host.getNameLabel(conn);
            if (restore) {
                conn = restoreHostConfig(conn, url, hostUrl, session, host, file);
                System.out.println("  staged it on " + name + "'s backup partition - it takes effect only "
                        + "after booting that host from the installer and choosing Restore");
            } else {
                System.out.println("  not restoring it (pass restore=true to stage it on "
                        + name + "'s backup partition)");
            }

            file.delete();
            System.out.println("OK: backup-host-config");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Close the connection's HTTP connection pool after a long transfer, so the next XenAPI call opens a
     * fresh one - the previous JsonRpcClient's one keep-alive connection sat idle for as long as the
     * transfer took, and a network that dropped it meanwhile leaves the next call hanging until the socket
     * times out. Connection has no public way to discard its pooled connections or to attach a custom
     * JsonRpcClient to an existing session at the same time, so build a fresh Connection (still trusting
     * the host's certificate, like connect() does) and set its session reference directly - there is no
     * public setter for that field.
     */
    private static Connection dropIdleConnection(Connection conn, String url) throws Exception {
        Connection fresh = new Connection(new JsonRpcClient(trustingHttpClient(), new URL(url + "/jsonrpc")));
        java.lang.reflect.Field sessionField = Connection.class.getDeclaredField("sessionReference");
        sessionField.setAccessible(true);
        sessionField.set(fresh, conn.getSessionReference());
        return fresh;
    }

    /**
     * Uploads a backup to a host - over a connection opened to THAT host's own address - and throws if
     * the task reports it was refused. Returns the (possibly renewed) connection to continue with.
     *
     * <p>An upload answers 200 as soon as it has read the request headers, because the client waits for
     * that before it starts sending the file. The outcome therefore cannot be in the status line: it
     * arrives on a task you create first, name in the URL, and poll once the upload has finished.
     */
    private static Connection restoreHostConfig(Connection conn, String apiUrl,
            String hostUrl, String session, Host host, java.io.File file) throws Exception {
        Task task = Task.create(conn, "host_restore", "restoring a configuration backup");
        try {
            HttpPut put = new HttpPut(hostUrl + "/host_restore?session_id=" + session
                    + "&ref=" + host.toWireString() + "&task_id=" + task.toWireString());
            // Stream the file rather than reading it into memory first; the entity reports the file's
            // own length as the Content-Length the server needs up front.
            put.setEntity(new org.apache.hc.core5.http.io.entity.FileEntity(
                    file, org.apache.hc.core5.http.ContentType.APPLICATION_OCTET_STREAM));
            try (CloseableHttpClient http = trustingHttpClient()) {
                http.execute(put, resp -> EntityUtils.toString(resp.getEntity()));
            }
            // As above: the connection sat idle for as long as the upload took. Reconnect to the
            // coordinator: the upload went to the host itself, but a pool member refuses API calls.
            conn = dropIdleConnection(conn, apiUrl);

            while (task.getStatus(conn) == Types.TaskStatusType.PENDING) Thread.sleep(500);
            if (task.getStatus(conn) != Types.TaskStatusType.SUCCESS) {
                // error_info is declared as a SET of strings, and the Java binding hands back a real
                // Set - so there is no "last element" to read the detail from. Print it whole rather
                // than indexing into something unordered; see the WLB example, where guessing at an
                // order silently lied.
                throw new IllegalStateException("refused " + task.getErrorInfo(conn));
            }
            return conn;
        } finally {
            task.destroy(conn);
        }
    }
}
