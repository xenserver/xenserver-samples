package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.PoolConnection.connect;

public final class ListTemplates {
    private ListTemplates() {
    }

    /**
     * List templates.
     *
     * <p>Enumerate the pool's VM templates, both built-in and custom.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ListTemplates.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        java.util.List<VM.Record> templates = new java.util.ArrayList<>();
        for (VM.Record v : VM.getAllRecords(conn).values())
            // A snapshot is a template too (is_a_template is set on every snapshot), so leave those out.
            if (v.isATemplate && !v.isASnapshot) templates.add(v);
        templates.sort(java.util.Comparator.comparing((VM.Record r) -> r.nameLabel));
        System.out.println("Templates (" + templates.size() + "):");
        int shown = 0;
        for (VM.Record t : templates) {
            if (shown++ >= 8) break;
            boolean isDefault = t.otherConfig.containsKey("default_template");
            System.out.println("  - " + t.nameLabel + (isDefault ? " [built-in]" : ""));
        }
        System.out.println("OK: list-templates");
        Session.logout(conn);
    }
}
