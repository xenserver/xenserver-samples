package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class VmFromSnapshot {
    private VmFromSnapshot() {
    }

    /**
     * Create a VM and a template from a snapshot.
     *
     * <p>Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * VmFromSnapshot.run("https://xenserver", "root", password, "db-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // A snapshot is a VM record with is_a_snapshot (and is_a_template) set, and cloning it gives a
            // custom template that stands on its own while the snapshot stays put.
            VM vm = vmByName(conn, vmName);
            VM snapshot = vm.snapshot(conn, "sdk-example-source-snapshot");
            System.out.println("Snapshot of " + vmName + " taken");

            // A clone of a snapshot is a template, not another snapshot: it stands on its own instead of
            // being filed under the original VM. Provision it to get an ordinary VM you can start.
            VM newVm = snapshot.createClone(conn, "sdk-example-vm-from-snapshot");
            provision(conn, newVm);
            System.out.printf("  new VM:      %s (is_a_template=%s)%n",
                newVm.getNameLabel(conn), newVm.getIsATemplate(conn));

            // Another clone, left as the template it already is: a starting point to stamp more VMs from.
            VM template = snapshot.createClone(conn, "sdk-example-template-from-snapshot");
            System.out.printf("  new template:%s (is_a_template=%s)%n",
                template.getNameLabel(conn), template.getIsATemplate(conn));

            // Each clone owns its own disks, and so does the snapshot itself.
            destroyVmAndDisks(conn, newVm);
            destroyVmAndDisks(conn, template);
            destroyVmAndDisks(conn, snapshot);
            System.out.println("OK: vm-from-snapshot");
        } finally {
            Session.logout(conn);
        }
    }
}
