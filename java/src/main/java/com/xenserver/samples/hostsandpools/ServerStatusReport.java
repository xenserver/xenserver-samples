package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;

import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class ServerStatusReport {
    private ServerStatusReport() {
    }

    /**
     * Collect a server status report.
     *
     * <p>Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the
     * whole bundle, then download a smaller one covering only the sections you pick.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Report on the coordinator. Each host answers for itself, so which one you ask decides
            // whose logs you get - support normally wants every host, one download each.
            Host host = Pool.getAll(conn).iterator().next().getMaster(conn);
            System.out.println("Status report for " + host.getNameLabel(conn));

            // The host publishes a catalogue of the sections it can report on, each with a size
            // estimate and whether it may contain personal data, so a client can offer an informed
            // choice rather than hard-coding the list.
            org.w3c.dom.NodeList capabilities = javax.xml.parsers.DocumentBuilderFactory.newInstance()
                .newDocumentBuilder()
                .parse(new org.xml.sax.InputSource(new java.io.StringReader(
                    host.getSystemStatusCapabilities(conn))))
                .getElementsByTagName("capability");
            java.util.List<String> keys = new java.util.ArrayList<>();
            java.util.List<String> defaults = new java.util.ArrayList<>();
            for (int i = 0; i < capabilities.getLength(); i++) {
                org.w3c.dom.Element capability = (org.w3c.dom.Element) capabilities.item(i);
                String key = capability.getAttribute("key");
                keys.add(key);
                if ("yes".equals(capability.getAttribute("default-checked"))) defaults.add(key);
                System.out.printf("  %-22s max %9s bytes  default=%-3s pii=%s%n",
                    key, capability.getAttribute("max-size"),
                    capability.getAttribute("default-checked"), capability.getAttribute("pii"));
            }

            // The download is an HTTP transfer alongside the API, so the session id travels in the
            // query string.
            String session = conn.getSessionReference();
            // Take the sections the host marks default-checked: asking for every section can mean
            // gigabytes (VM memory dumps, every log) and a long wait while the host builds it.
            long whole = fetchStatusReport(url, session, defaults);
            System.out.printf("default sections (%d of %d): %d bytes%n", defaults.size(), keys.size(), whole);

            // Pick a real, small section from the host's own catalogue rather than assuming a name: the
            // catalogue is server-defined (xen-bugtool's own --capabilities output), not a fixed client
            // list, and "xenserver-config" isn't one of the real keys any host actually publishes.
            String subsetKey = keys.get(0);
            for (String k : keys) {
                if (k.equals("firstboot") || k.equals("network-status")) { subsetKey = k; break; }
            }
            long subset = fetchStatusReport(url, session, java.util.Arrays.asList(subsetKey));
            System.out.printf("%s only:   %d bytes%n", subsetKey, subset);
            if (subset >= whole)
                System.out.println("  ERROR: selecting fewer sections did not produce a smaller bundle");

            System.out.println("OK: server-status-report");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Downloads the bundle for the given capability keys (a tar archive) to a temp file, streaming it - a
     * report can be large - and returns its size. This example then deletes it; you'd keep it.
     */
    private static long fetchStatusReport(String url, String session,
                                          java.util.List<String> entries) throws Exception {
        java.io.File file = java.io.File.createTempFile("sdk-example-status-", ".tar");
        try {
            HttpGet get = new HttpGet(url + "/system-status?session_id=" + session + "&output=tar"
                + "&entries=" + String.join(",", entries));
            try (CloseableHttpClient http = trustingHttpClient()) {
                http.execute(get, resp -> {
                    try (java.io.InputStream in = resp.getEntity().getContent()) {
                        java.nio.file.Files.copy(in, file.toPath(),
                            java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    }
                    return null;
                });
            }
            return file.length();
        } finally {
            file.delete();
        }
    }
}
