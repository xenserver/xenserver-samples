package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class VbdInventory {
    private VbdInventory() {
    }

    /**
     * Inventory a VM's disks.
     *
     * <p>List a VM's attached disks and the size of each.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * VbdInventory.run("https://xenserver", "root", password, "db-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);
        System.out.println("Disks of '" + vm.getNameLabel(conn) + "':");
        for (VBD vbd : vm.getVBDs(conn)) {
            VBD.Record rec = vbd.getRecord(conn);
            if (rec.type != Types.VbdType.DISK) continue;
            VDI vdi = vbd.getVDI(conn);
            long size = vdi.isNull() ? 0 : vdi.getVirtualSize(conn) / GiB;
            System.out.println("  - device " + rec.userdevice + ": " + size + " GiB");
        }
        System.out.println("OK: vbd-inventory");
        Session.logout(conn);
    }
}
