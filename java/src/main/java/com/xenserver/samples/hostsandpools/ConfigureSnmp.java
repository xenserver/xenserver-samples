package com.xenserver.samples.hostsandpools;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureSnmp {
    private static final String RESULT = "result";   // the plugin wraps every answer in it

    private ConfigureSnmp() {
    }

    /**
     * Configure SNMP monitoring.
     *
     * <p>Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it
     * with a community string and a trap destination, read it back, then put the original configuration
     * back.
     *
     * <p>On every host, through the snmp plugin: read its configuration, enable it with a community
     * string and a trap destination, read it back, then put the original configuration back.
     *
     * <p>trapDestination: the "nmss" list must contain at least one non-empty entry pointed at it (an
     * empty list never configures where traps actually go - arguably the main point of "configure SNMP
     * monitoring"). Plugin calls are per-host, so configure every host, and restore each one to what it
     * had before, rather than assuming it was disabled.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureSnmp.run("https://xenserver", "root", password, "192.0.2.50");
     * }</pre>
     */
    public static void run(String url, String user, String password, String trapDestination)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            ObjectMapper mapper = new ObjectMapper();
            String config = "{\"common\":{\"enabled\":\"yes\",\"debug_log\":\"no\"},"
                + "\"agent\":{\"v2c\":\"yes\",\"v3\":\"no\",\"community\":\"sdk-community\",\"user_name\":\"\","
                + "\"authentication_password\":\"\",\"authentication_protocol\":\"\","
                + "\"privacy_password\":\"\",\"privacy_protocol\":\"\"},"
                // Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
                + "\"nmss\":[{\"uuid\":\"" + UUID.randomUUID() + "\",\"address\":\"" + trapDestination
                + "\",\"port\":162,\"v2c\":\"yes\",\"v3\":\"no\","
                + "\"community\":\"sdk-community\",\"user_name\":\"\",\"authentication_password\":\"\","
                + "\"authentication_protocol\":\"\",\"privacy_password\":\"\",\"privacy_protocol\":\"\"}]}";
            for (Host host : Host.getAll(conn)) {
                // Keep the host's own configuration so it can be put back, rather than left disabled.
                // Parsed with Jackson (already a dependency of the binding) rather than hand-rolled: the
                // result nests an "nmss" array of objects, which a quick string search can't reliably peel
                // off.
                JsonNode before = call(conn, mapper, host, "get-config", Map.of()).path(RESULT);

                Map<String, String> args = new HashMap<>();
                args.put("config", config);
                // The plugin reports a refused config in its answer, not as an API error: check it.
                JsonNode answer = call(conn, mapper, host, "set-config", args);
                if (answer.path("code").asInt() != 0)
                    throw new IllegalStateException(
                        "set-config refused the configuration: " + answer.path("message").asText());
                JsonNode status = call(conn, mapper, host, "status", Map.of()).path(RESULT);
                JsonNode cfg = call(conn, mapper, host, "get-config", Map.of()).path(RESULT);
                String label = host.getNameLabel(conn);
                System.out.println(label + ": SNMP enabled: " + status.path("enabled").asText()
                        + " / " + status.path("active").asText());
                JsonNode nmss = cfg.path("nmss");
                System.out.println("  community: " + cfg.path("agent").path("community").asText()
                        + ", trap destination: "
                        + (nmss.size() > 0 ? nmss.get(0).path("address").asText() : "(none)"));

                // Put back whatever configuration the host had before, rather than leaving it disabled.
                Map<String, String> restore = new HashMap<>();
                restore.put("config", mapper.writeValueAsString(before));
                JsonNode restoreAnswer = call(conn, mapper, host, "set-config", restore);
                if (restoreAnswer.path("code").asInt() != 0)
                    throw new IllegalStateException("set-config refused to restore the configuration: "
                        + restoreAnswer.path("message").asText());
            }
            System.out.println("OK: configure-snmp");
        } finally {
            Session.logout(conn);
        }
    }

    /** One call to the snmp plugin, parsed as JSON - every function it exports answers with JSON. */
    private static JsonNode call(Connection conn, ObjectMapper mapper, Host host, String fn,
            Map<String, String> args) throws Exception {
        return mapper.readTree(host.callPlugin(conn, "snmp", fn, args));
    }
}
