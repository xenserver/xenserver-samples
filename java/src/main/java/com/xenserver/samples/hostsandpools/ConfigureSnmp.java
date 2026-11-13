package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureSnmp {
    private ConfigureSnmp() {
    }

    /**
     * Configure SNMP monitoring.
     *
     * <p>Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it
     * with a community string, then read the configuration and running status back.
     *
     * <p>trap_destination: the "nmss" list must contain at least one non-empty entry pointed at it (an
     * empty list never configures where traps actually go - arguably the main point of "configure SNMP
     * monitoring". Loop every host, same reasoning as configure-nrpe; restore each host to
     * {"common":{"enabled":"no"}} (a partial config - real set-config merges) at the end.
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
            String config = "{\"common\":{\"enabled\":\"yes\",\"debug_log\":\"no\"},"
                + "\"agent\":{\"v2c\":\"yes\",\"v3\":\"no\",\"community\":\"sdk-community\",\"user_name\":\"\","
                + "\"authentication_password\":\"\",\"authentication_protocol\":\"\","
                + "\"privacy_password\":\"\",\"privacy_protocol\":\"\"},"
                // Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
                + "\"nmss\":[{\"uuid\":\"" + java.util.UUID.randomUUID() + "\",\"address\":\"" + trapDestination
                + "\",\"port\":162,\"v2c\":\"yes\",\"v3\":\"no\","
                + "\"community\":\"sdk-community\",\"user_name\":\"\",\"authentication_password\":\"\","
                + "\"authentication_protocol\":\"\",\"privacy_password\":\"\",\"privacy_protocol\":\"\"}]}";
            for (Host host : Host.getAll(conn)) {
                Map<String, String> args = new java.util.HashMap<>();
                args.put("config", config);
                // The plugin reports a refused config in its answer, not as an API error: check it.
                String answer = host.callPlugin(conn, "snmp", "set-config", args);
                if (!answer.replace(" ", "").contains("\"code\":0"))
                    throw new RuntimeException("set-config refused the configuration: " + answer);
                String status = host.callPlugin(conn, "snmp", "status", new java.util.HashMap<>());
                String cfg = host.callPlugin(conn, "snmp", "get-config", new java.util.HashMap<>());
                String label = host.getNameLabel(conn);
                System.out.println(label + ": SNMP enabled: " + jsonField(status, "enabled")
                        + " / " + jsonField(status, "active"));
                System.out.println("  community: " + jsonField(cfg, "community")
                        + ", trap destination: " + jsonField(cfg, "address"));
                Map<String, String> restore = new java.util.HashMap<>();
                restore.put("config", "{\"common\":{\"enabled\":\"no\"}}");
                host.callPlugin(conn, "snmp", "set-config", restore); // restore
            }
            System.out.println("OK: configure-snmp");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Minimal extractor for a "key":"value" pair in the SNMP plugin's JSON reply (avoids a JSON
     * dependency).
     */
    private static String jsonField(String json, String key) {
        java.util.regex.Matcher m = java.util.regex.Pattern
            .compile("\"" + key + "\"\\s*:\\s*\"([^\"]*)\"").matcher(json);
        return m.find() ? m.group(1) : "";
    }
}
