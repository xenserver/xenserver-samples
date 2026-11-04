package com.xenserver.samples.securityandaccess;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Role;
import com.xensource.xenapi.Session;

import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

public final class ListRoles {
    private ListRoles() {
    }

    /**
     * List RBAC roles.
     *
     * <p>Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to
     * users.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ListRoles.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        // Role is the one class XenCenter still bulk-downloads; RBAC subjects map to these roles. Role records
        // include every permission too; the roles a user can be granted are the ones made of permissions
        // (non-empty subroles), as xe role-list shows.
        Set<String> roles = new java.util.TreeSet<>(); // distinct + sorted by name
        for (Role.Record r : Role.getAllRecords(conn).values()) if (!r.subroles.isEmpty()) roles.add(r.nameLabel);
        StringBuilder first = new StringBuilder();
        int shown = 0;
        for (String name : roles) {
            if (shown++ >= 8) break;
            if (first.length() > 0) first.append(", ");
            first.append(name);
        }
        System.out.println("Roles (" + roles.size() + "): " + first);
        System.out.println("OK: list-roles");
        Session.logout(conn);
    }
}
