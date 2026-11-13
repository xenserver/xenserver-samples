package com.xenserver.samples.migration;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.Helpers.awaitTask;
import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.diskVdis;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class StorageMigrate {
    private StorageMigrate() {
    }

    /**
     * Storage live-migration.
     *
     * <p>Move a running VM's virtual disk to a different storage repository while the VM keeps running —
     * live storage migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
     *
     * <p>Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
     * so this works on a throwaway copy of sourceVm, a VM with a guest OS and PV drivers. (A halted VM's
     * disk moves too, without the guest; what VDI.poolMigrate always needs is a VM to move the disk for -
     * a VDI no VBD points at fails VDI_NEEDS_VM_FOR_MIGRATE.)
     *
     * <p>Run it:
     *
     * <pre>{@code
     * StorageMigrate.run("https://xenserver", "root", password, "web-01", "sdk-example-storagemigrate");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String sourceVm, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = copyOfGuest(conn, sourceVm, newVmName);
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);
        VDI vdi = diskVdis(conn, vm).iterator().next();
        SR sourceSr = vdi.getSR(conn);
        System.out.println("Disk is on SR: " + sourceSr.getNameLabel(conn));

        // Pick a different SR that holds disks and that the VM's host can reach (an attached PBD there).
        Host host = vm.getResidentOn(conn);
        SR destSr = null;
        for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet()) {
            SR.Record r = e.getValue();
            if (e.getKey().equals(sourceSr) || "iso".equals(r.contentType)
                    || "iso".equals(r.type) || "udev".equals(r.type))
                continue;
            boolean reachable = false;
            for (PBD pbd : r.PBDs)
                if (pbd.getHost(conn).equals(host) && pbd.getCurrentlyAttached(conn)) { reachable = true; break; }
            if (reachable) { destSr = e.getKey(); break; }
        }
        // poolMigrate returns the disk's new VDI: the copy on the destination SR replaces the original.
        // Copying a disk takes minutes, so run it as a task (see awaitTask).
        vdi = new VDI(awaitTask(conn, vdi.poolMigrateAsync(conn, destSr, new java.util.HashMap<>())));

        System.out.println("Disk moved to:  " + vdi.getSR(conn).getNameLabel(conn));

        // Tidy up: the VM and the disks it now owns.
        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: storage-migrate");
        Session.logout(conn);
    }
}
