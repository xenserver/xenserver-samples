package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class EditVmProperties {
    private EditVmProperties() {
    }

    /**
     * Edit VM properties.
     *
     * <p>Change a VM's description and custom metadata, then read the changes back.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * EditVmProperties.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);

        String originalDesc = vm.getNameDescription(conn);
        vm.setNameDescription(conn, "Edited by the SDK example");
        vm.addToOtherConfig(conn, "sdk_example", "true");
        System.out.println("New description: " + vm.getNameDescription(conn));
        System.out.println("other_config[sdk_example] = " + vm.getOtherConfig(conn).get("sdk_example"));

        vm.setNameDescription(conn, originalDesc);
        vm.removeFromOtherConfig(conn, "sdk_example");
        System.out.println("OK: edit-vm-properties");
        Session.logout(conn);
    }
}
