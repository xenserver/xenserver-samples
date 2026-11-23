package com.xenserver.samples;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.JsonRpcClient;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.client5.http.ssl.NoopHostnameVerifier;
import org.apache.hc.client5.http.ssl.SSLConnectionSocketFactory;
import org.apache.hc.core5.ssl.SSLContexts;
import org.apache.hc.core5.util.TimeValue;
import org.apache.hc.core5.util.Timeout;

import java.net.URI;
import javax.net.ssl.SSLContext;

/**
 * Connecting to a pool: accept the host's self-signed certificate, log in, and follow HOST_IS_SLAVE to the
 * coordinator when given a pool member.
 *
 * <p>Accepting the certificate without checking it suits a test pool. In production, check it: give the
 * hosts a certificate from a CA you trust, or trust the pool's own certificate explicitly.
 */
public final class PoolConnection {
    private PoolConnection() {
    }

    // --- connect ---
    public static Connection connect(String url, String user, String password) throws Exception {
        CloseableHttpClient http = trustingHttpClient();
        try {
            return login(http, url, user, password);
        } catch (Types.HostIsSlave e) {
            // A pool member names the coordinator's address; reconnect there (assuming the coordinator
            // is up). Java SDKs up to 26.22 read that address as "" under JSON-RPC: say so rather than
            // connecting to "https://".
            if (e.masterIPAddress == null || e.masterIPAddress.isEmpty())
                throw new CoordinatorUnknown(url);
            return login(http, "https://" + e.masterIPAddress, user, password);
        }
    }

    /**
     * HOST_IS_SLAVE from a pool member, without the coordinator's address (see connect).
     */
    public static class CoordinatorUnknown extends Exception {
        CoordinatorUnknown(String url) {
            super(url + " is a pool member, and this SDK did not report the coordinator's address");
        }
    }

    /**
     * An HTTP client that trusts the host's self-signed certificate. (Apache HttpClient 5 uses its own SSL
     * context, so we configure it here rather than relying on JVM-wide defaults.)
     */
    public static CloseableHttpClient trustingHttpClient() throws Exception {
        SSLContext ssl = SSLContexts.custom()
            .loadTrustMaterial((chain, authType) -> true)
            .build();
        SSLConnectionSocketFactory sslsf = new SSLConnectionSocketFactory(ssl, NoopHostnameVerifier.INSTANCE);
        // A synchronous call blocks until the operation finishes, and checkpointing, copying or exporting a
        // large VM can take many minutes: wait up to an hour for the answer rather than HttpClient's
        // three-minute default. (For anything longer, use the Async form and poll the task - see
        // WaitForTask.)
        PoolingHttpClientConnectionManager cm = PoolingHttpClientConnectionManagerBuilder.create()
            .setSSLSocketFactory(sslsf)
            .setDefaultConnectionConfig(ConnectionConfig.custom().setSocketTimeout(Timeout.ofHours(1)).build())
            .build();
        // Close a pooled connection once it has been idle for 30 seconds, so the next call opens a fresh one.
        // While a long HTTP transfer (a host backup, a disk export) runs, the API connection sits idle, and a
        // network that silently drops it meanwhile would leave the next call hanging until the socket
        // times out.
        return HttpClients.custom().setConnectionManager(cm).evictIdleConnections(TimeValue.ofSeconds(30)).build();
    }

    private static Connection login(CloseableHttpClient http, String url, String user, String password) throws Exception {
        Connection conn = new Connection(new JsonRpcClient(http, URI.create(url + "/jsonrpc").toURL()));
        Session.loginWithPassword(conn, user, password, "1.0", "sdk-examples");
        return conn;
    }
}
