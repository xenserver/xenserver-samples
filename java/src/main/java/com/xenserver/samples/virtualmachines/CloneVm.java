package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CloneVm {
    private CloneVm() {
    }

    /**
     * Clone a VM.
     *
     * <p>Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full
     * copy — the quick way to stamp out new VMs from a halted "golden" image.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CloneVm.run("https://xenserver", "root", password, "db-01", "sdk-example-clone");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String vmName, String cloneName) throws Exception {
        Connection conn = connect(url, user, password);
        // Unlike Copy (a full, independent copy onto a chosen SR), Clone is a fast copy-on-write
        // duplicate on the same SR — ideal for a halted "golden" VM.
        VM source = vmByName(conn, vmName);
        VM clone = source.createClone(conn, cloneName);
        System.out.println("Cloned '" + source.getNameLabel(conn) + "' → " + clone.getNameLabel(conn));
        System.out.println("Clone has " + clone.getVBDs(conn).size() + " VBD(s)");

        // Tidy up: destroy the clone and its (owned) disks.
        destroyVmAndDisks(conn, clone);
        System.out.println("OK: clone-vm");
        Session.logout(conn);
    }
}
