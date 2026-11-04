package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class RenameObject {
    private RenameObject() {
    }

    /**
     * Rename an object.
     *
     * <p>Change an object's name and read it back — how any object is renamed.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * RenameObject.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);
        String original = vm.getNameLabel(conn);
        vm.setNameLabel(conn, "sdk-renamed");
        System.out.println("Renamed '" + original + "' → '" + vm.getNameLabel(conn) + "'");
        vm.setNameLabel(conn, original); // restore so the example is repeatable
        System.out.println("OK: rename-object");
        Session.logout(conn);
    }
}
