package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class ConvertToTemplate {
    private ConvertToTemplate() {
    }

    /**
     * Convert a VM to a template.
     *
     * <p>Turn a VM into a reusable custom template. This is a one-way operation.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConvertToTemplate.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-totemplate");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm); // now a real (halted) VM
        System.out.println("is_a_template after provision: " + vm.getIsATemplate(conn));

        // Converting a VM to a custom template is a one-way operation.
        vm.setIsATemplate(conn, true);
        System.out.println("is_a_template after convert:  " + vm.getIsATemplate(conn));

        destroyVmAndDisks(conn, vm);
        System.out.println("OK: convert-to-template");
        Session.logout(conn);
    }
}
