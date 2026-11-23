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

        // Pick a different SR that holds disks, that the VM's host can reach (an attached PBD there),
        // and that has room for the disk - a host's local SR is often too small for a VM's disk. Scan a
        // candidate before trusting its free space: the size and utilisation xapi reports are only as
        // fresh as the SR's last scan, and can claim room the storage doesn't have. Live storage migration
        // copies a snapshot of the disk and mirrors the running disk on top of it, so the destination needs
        // room for the disk twice over (a thick-provisioned LVM SR allocates both).
        final long GiB = 1024L * 1024 * 1024;
        Host host = vm.getResidentOn(conn);
        long size = vdi.getVirtualSize(conn);
        SR destSr = null;
        for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet()) {
            SR sr = e.getKey();
            SR.Record r = e.getValue();
            boolean holdsDisks = !"iso".equals(r.contentType) && !"iso".equals(r.type) && !"udev".equals(r.type);
            if (!sr.equals(sourceSr) && holdsDisks && attachedTo(conn, r, host)) {
                sr.scan(conn);
                if (sr.getPhysicalSize(conn) - sr.getPhysicalUtilisation(conn) >= 2 * size) { destSr = sr; break; }
            }
        }
        if (destSr == null) {
            vm.hardShutdown(conn);
            destroyVmAndDisks(conn, vm);
            throw new IllegalStateException("no other SR attached to " + host.getNameLabel(conn)
                    + " has room for the " + (size / GiB) + " GiB disk twice over");
        }
        // poolMigrate returns the disk's new VDI: the copy on the destination SR replaces the original.
        // Copying a disk takes minutes, so run it as a task (see awaitTask).
        vdi = new VDI(awaitTask(conn, vdi.poolMigrateAsync(conn, destSr, new java.util.HashMap<>())));

        System.out.println("Disk moved to:  " + vdi.getSR(conn).getNameLabel(conn));

        // Tidy up: the VM and the disks it now owns.
        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("Cleaned up the example VM.");
        System.out.println("OK: storage-migrate");
        Session.logout(conn);
    }

    /**
     * Whether an SR is attached to a host (it has a plugged PBD there).
     */
    private static boolean attachedTo(Connection conn, SR.Record sr, Host host) throws Exception {
        for (PBD pbd : sr.PBDs)
            if (pbd.getHost(conn).equals(host) && pbd.getCurrentlyAttached(conn)) return true;
        return false;
    }
}
