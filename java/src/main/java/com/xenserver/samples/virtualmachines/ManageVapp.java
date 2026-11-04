package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VMAppliance;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVapp {
    private ManageVapp() {
    }

    /**
     * Manage a vApp.
     *
     * <p>Group VMs into an appliance that starts and stops together in a defined order, start and shut it
     * down as a unit, then remove it.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageVapp.run("https://xenserver", "root", password, "db-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = VM.getByNameLabel(conn, vmName).iterator().next();

            VMAppliance.Record spec = new VMAppliance.Record();
            spec.nameLabel = "sdk-example-vapp";
            spec.nameDescription = "Created by the SDK example";
            VMAppliance vapp = VMAppliance.create(conn, spec);

            // `order` decides the sequence: ascending to start, descending to shut down. That ordering
            // is the reason to use a vApp rather than selecting several VMs.
            vm.setAppliance(conn, vapp);
            vm.setOrder(conn, 0L);
            vm.setStartDelay(conn, 5L);

            vapp.start(conn, false);
            System.out.println("Started:        " + vm.getPowerState(conn));

            // shutdown tries each VM's clean shutdown and falls back to a hard one. cleanShutdown alone
            // fails OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers).
            vapp.shutdown(conn);
            System.out.println("Shut down:      " + vm.getPowerState(conn));

            // Detach with the null REFERENCE, not Java's null: the binding doesn't turn null into
            // OpaqueRef:NULL, and a real host refuses what it sends with INTERNAL_ERROR.
            vm.setAppliance(conn, new VMAppliance("OpaqueRef:NULL"));
            vapp.destroy(conn);
            System.out.println("OK: manage-vapp");
        } finally {
            Session.logout(conn);
        }
    }
}
