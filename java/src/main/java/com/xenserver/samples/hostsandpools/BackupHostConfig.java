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
import java.util.Map;

import static com.xenserver.samples.Helpers.hostUrl;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class BackupHostConfig {
    private BackupHostConfig() {
    }

    /**
     * Back up a host's configuration.
     *
     * <p>Download a host's configuration backup and hand it back as a restore would — and watch another
     * host's backup be refused.
     *
     * <p>Both /host_backup and /host_restore are served only by whichever host physically accepted the
     * HTTP connection - the handler ignores any ref= in the query string entirely, there is no forwarding
     * to another pool member. So backing up/restoring a host means opening the connection to THAT host's
     * own address, not to the pool's (coordinator) url - a restore sent to the wrong host's connection
     * silently restores the WRONG host, not the one named by ref=. ref= is kept in the query string purely
     * for log-readability (a real host ignores it; it is not what makes this correct).
     *
     * <p>Run it:
     *
     * <pre>{@code
     * BackupHostConfig.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            java.util.List<Host> hosts = new java.util.ArrayList<Host>(Host.getAll(conn));
            Host host = hosts.get(0);
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
            System.out.printf("  wrote %d bytes to %s%n", file.length(), file.getName());
            // The connection's one keep-alive HTTP connection sat idle for as long as the download
            // took; a network that silently dropped it meanwhile would otherwise leave the next call
            // (Task.create below) hanging until the socket times out, so get a fresh one for the same
            // session before making another API call.
            conn = dropIdleConnection(conn, url);

            Map.Entry<String, Connection> restored = restoreHostConfig(conn, url, hostUrl, session, host, file);
            conn = restored.getValue();
            System.out.println("  restoring it to " + host.getNameLabel(conn) + ": " + restored.getKey());
            if (hosts.size() > 1) {
                Host other = hosts.get(1);
                String result;
                try {
                    String otherUrl = hostUrl(url, other.getAddress(conn));
                    Map.Entry<String, Connection> r = restoreHostConfig(conn, url, otherUrl, session, other, file);
                    conn = r.getValue();
                    result = r.getKey();
                } catch (Exception e) {
                    // A real pool's hosts are all reachable from a management client; this only guards an
                    // environment (a host whose address isn't routable from here, say) where that isn't
                    // true, so the example still finishes cleanly.
                    result = "could not connect directly (" + e + ")";
                }
                System.out.println("  restoring it to " + other.getNameLabel(conn) + ": " + result);
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
     * Uploads a backup to a host - over a connection opened to THAT host's own address - and reports what
     * the task says about it, alongside the (possibly renewed) connection to continue with.
     *
     * <p>An upload answers 200 as soon as it has read the request headers, because the client waits for
     * that before it starts sending the file. The outcome therefore cannot be in the status line: it
     * arrives on a task you create first, name in the URL, and poll once the upload has finished.
     */
    private static Map.Entry<String, Connection> restoreHostConfig(Connection conn, String apiUrl,
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
            String result;
            if (task.getStatus(conn) == Types.TaskStatusType.SUCCESS) {
                result = "accepted";
            } else {
                // error_info is declared as a SET of strings, and the Java binding hands back a real
                // Set - so there is no "last element" to read the detail from. Print it whole rather
                // than indexing into something unordered; see the WLB example, where guessing at an
                // order silently lied.
                result = "refused " + task.getErrorInfo(conn);
            }
            return new java.util.AbstractMap.SimpleEntry<>(result, conn);
        } finally {
            task.destroy(conn);
        }
    }
}
