package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateVm {
    private CreateVm() {
    }

    /**
     * Create a VM from a template.
     *
     * <p>Clone one of the built-in templates and provision the clone into a real, installable VM.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateVm.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vm");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM template = templateByName(conn, templateName);
        System.out.println("Using template: " + template.getNameLabel(conn));

        VM vm = template.createClone(conn, newVmName);
        System.out.println("Cloned new VM: " + vm.getUuid(conn));

        provision(conn, vm);
        System.out.println("Provisioned. is_a_template = " + vm.getIsATemplate(conn));

        destroyVmAndDisks(conn, vm);
        System.out.println("Cleaned up the example VM.");

        System.out.println("OK: create-vm");
        Session.logout(conn);
    }
}
