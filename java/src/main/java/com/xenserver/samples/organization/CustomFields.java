package com.xenserver.samples.organization;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CustomFields {
    private CustomFields() {
    }

    /**
     * Custom fields.
     *
     * <p>Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the
     * object.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CustomFields.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        // XenCenter's custom fields are stored in other_config under "XenCenter.CustomFields.<name>".
        VM vm = vmByName(conn, vmName);
        final String key = "XenCenter.CustomFields.Owner";
        vm.addToOtherConfig(conn, key, "Platform Team");
        System.out.println("Custom field Owner = " + vm.getOtherConfig(conn).get(key));

        vm.removeFromOtherConfig(conn, key);
        System.out.println("OK: custom-fields");
        Session.logout(conn);
    }
}
