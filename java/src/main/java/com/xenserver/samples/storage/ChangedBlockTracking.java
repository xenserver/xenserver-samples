package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.PoolConnection.connect;

public final class ChangedBlockTracking {
    private ChangedBlockTracking() {
    }

    /**
     * Back up with changed block tracking.
     *
     * <p>Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which
     * blocks differ, then release the older snapshot's data while keeping the change metadata the next
     * incremental needs.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ChangedBlockTracking.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = null;
            VM.Record record = null;
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record v = e.getValue();
                if (!v.isATemplate && !v.isControlDomain && !v.isASnapshot && !v.VBDs.isEmpty()) {
                    vm = e.getKey(); record = v; break;
                }
            }
            if (vm == null) throw new Exception("no VM with a disk");
            System.out.println("Backing up " + record.nameLabel);

            // CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it.
            // It can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
            VDI live = firstDisk(conn, vm);
            boolean wasEnabled = live.getCbtEnabled(conn);
            if (!wasEnabled) live.enableCbt(conn);

            VM first = vm.snapshot(conn, "cbt-backup-1");
            VM second = vm.snapshot(conn, "cbt-backup-2");
            VDI vdiFrom = firstDisk(conn, first);
            VDI vdiTo = firstDisk(conn, second);

            // One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup
            // reads only those blocks, over NBD.
            byte[] bitmap = java.util.Base64.getDecoder().decode(vdiFrom.listChangedBlocks(conn, vdiTo));
            int changed = 0;
            for (byte b : bitmap) changed += Integer.bitCount(b & 0xFF);
            System.out.printf("  %d blocks of %d changed (%.1f MiB to copy, not %.1f MiB)%n",
                changed, bitmap.length * 8, changed * 64 / 1024.0,
                vdiTo.getVirtualSize(conn) / (1024.0 * 1024));

            // Release the older snapshot's blocks but keep its change metadata, so the next incremental
            // can still diff against it. data_destroy refuses a disk that a VM still uses (VDI_IN_USE), so
            // drop the older snapshot's VM record first, as a backup tool does. The VDI record stays; its
            // type changes.
            first.destroy(conn);
            vdiFrom.dataDestroy(conn);
            System.out.printf("  older snapshot is now type=%s, still cbt_enabled=%b%n",
                vdiFrom.getType(conn), vdiFrom.getCbtEnabled(conn));

            // Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own
            // disk if this example switched it on.
            destroyVmAndDisks(conn, second);
            vdiFrom.destroy(conn);
            if (!wasEnabled) live.disableCbt(conn);
            System.out.println("OK: changed-block-tracking");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * The VDI behind a VM's first real disk (a CD drive is a VBD too).
     */
    private static VDI firstDisk(Connection conn, VM vm) throws Exception {
        for (VBD vbd : vm.getVBDs(conn))
            if (vbd.getType(conn) == Types.VbdType.DISK)
                return vbd.getVDI(conn);
        throw new Exception("no disk found");
    }
}
