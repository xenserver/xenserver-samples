package com.xenserver.samples.migration;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.moveDisksToSr;
import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class LiveMigrate {
    private LiveMigrate() {
    }

    /**
     * Live migrate a VM.
     *
     * <p>Move a running VM to another host in the pool with no downtime: check the destination can boot
     * it, live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and
     * PV drivers (source_vm), with its disks moved first to a shared storage repository (sr_name) so the
     * destination host can see them.
     *
     * <p>Moves a throwaway copy of sourceVm, a VM with a guest OS and PV drivers: live migration needs the
     * guest's cooperation (VM_LACKS_FEATURE without PV drivers). Only the VM's memory moves, so the
     * destination host has to see its disks already: a disk on local storage refuses with VM_REQUIRES_SR.
     * Put the copy's disks on the shared SR srName first.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * LiveMigrate.run("https://xenserver", "root", password, "web-01", "Shared NFS", "sdk-example-migrate");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String sourceVm, String srName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = copyOfGuest(conn, sourceVm, newVmName);
        moveDisksToSr(conn, vm, srByName(conn, srName, true));
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);

        Host sourceHost = vm.getResidentOn(conn);
        System.out.println("VM is running on: " + sourceHost.getNameLabel(conn));

        // Pick a different host in the pool to receive the VM.
        Host destHost = null;
        for (Host h : Host.getAllRecords(conn).keySet())
            if (!h.equals(sourceHost)) { destHost = h; break; }

        // Check the destination can boot it, then live-migrate (empty options = default live migration).
        vm.assertCanBootHere(conn, destHost);
        vm.poolMigrate(conn, destHost, new java.util.HashMap<>());

        System.out.println("Migrated to:      " + vm.getResidentOn(conn).getNameLabel(conn));
        System.out.println("Still running:    " + vm.getPowerState(conn));

        // Tidy up so the example is repeatable.
        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: live-migrate");
        Session.logout(conn);
    }
}
