package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.EntityUtils;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class RrdMetrics {
    private RrdMetrics() {
    }

    /**
     * Read RRD performance metrics.
     *
     * <p>Pull recent host performance samples from the RRD archives over the performance-data HTTP API,
     * parse the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space
     * utilisation per host).
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Map<String, String> nameByUuid = new java.util.HashMap<>();
            for (Host.Record h : Host.getAllRecords(conn).values()) nameByUuid.put(h.uuid, h.nameLabel);

            // The RRD time-series isn't a XenAPI call; read rrd_updates over HTTP. Legends look like
            // "AVERAGE:host:<uuid>:<datasource>"; values[] aligns to legend[].
            long start = System.currentTimeMillis() / 1000 - 300;
            HttpGet get = new HttpGet(url + "/rrd_updates?session_id=" + conn.getSessionReference() + "&host=true&start=" + start);
            get.addHeader("accept", "application/json");
            String body;
            try (CloseableHttpClient http = trustingHttpClient()) {
                body = http.execute(get, resp -> EntityUtils.toString(resp.getEntity()));
            }
            JsonNode root = new ObjectMapper().readTree(body);
            JsonNode legends = root.get("meta").get("legend");
            Map<String, Double> peak = new java.util.HashMap<>();
            for (JsonNode point : root.get("data")) {
                JsonNode values = point.get("values");
                for (int k = 0; k < legends.size(); k++) {
                    String[] parts = legends.get(k).asText().split(":");
                    if (parts[1].equals("host") && parts[3].equals("pvsaccelerator_space_utilization")) {
                        double value = values.get(k).asDouble();
                        if (Double.isNaN(value)) continue; // a gap in the series, not a real sample
                        peak.merge(parts[2], value, Math::max);
                    }
                }
            }
            for (Map.Entry<String, Double> e : peak.entrySet())
                System.out.printf("  %s: peak PVS cache utilisation %.0f%%%n", nameByUuid.get(e.getKey()), e.getValue());
            System.out.println("OK: rrd-metrics");
        } finally {
            Session.logout(conn);
        }
    }
}
