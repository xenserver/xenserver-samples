package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.moveDisksToSr;
import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class HostMaintenance {
    private HostMaintenance() {
    }

    /**
     * Enter &amp; exit maintenance mode.
     *
     * <p>Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running
     * guests to another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and
     * PV drivers (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation
     * something to move.
     *
     * <p>Pins a throwaway copy of sourceVm to the host so evacuation has work to do. Evacuation
     * live-migrates the guest, which needs its cooperation (VM_LACKS_FEATURE without PV drivers), so
     * sourceVm must have a guest OS with PV drivers.
     *
     * <p>Evacuation needs somewhere else in the pool that can actually see the VM's disk - a VM whose only
     * disk is on local (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a pool's
     * installation-time default SR is commonly local storage. Put the pinned VM's disk on a shared SR
     * explicitly rather than trusting whatever the pool default happens to be.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * HostMaintenance.run("https://xenserver", "root", password, "web-01", "Shared NFS", "sdk-example-maint");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String sourceVm, String srName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        // Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
        Host master = Pool.getAllRecords(conn).values().iterator().next().master;
        Host hostRef = null;
        for (Host h : Host.getAllRecords(conn).keySet())
            if (!h.equals(master)) { hostRef = h; break; }
        System.out.println("Maintenance host: " + hostRef.getNameLabel(conn));

        // Pin a running VM to that host so evacuation has something to move.
        VM vm = copyOfGuest(conn, sourceVm, newVmName);
        moveDisksToSr(conn, vm, srByName(conn, srName, true));
        vm.setAffinity(conn, hostRef);
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);
        System.out.println("Guest resident on:" + vm.getResidentOn(conn).getNameLabel(conn));

        // Enter maintenance mode: disable the host, then evacuate its guests.
        hostRef.disable(conn);
        System.out.println("After disable:    host.enabled = " + hostRef.getEnabled(conn));
        hostRef.evacuate(conn);
        System.out.println("After evacuate:   guest now on " + vm.getResidentOn(conn).getNameLabel(conn));

        // Exit maintenance mode.
        hostRef.enable(conn);
        System.out.println("After enable:     host.enabled = " + hostRef.getEnabled(conn));

        // Tidy up so the example is repeatable.
        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: host-maintenance");
        Session.logout(conn);
    }
}
