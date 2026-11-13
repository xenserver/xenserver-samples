package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CopyVm {
    private CopyVm() {
    }

    /**
     * Copy a VM.
     *
     * <p>Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks)
     * — distinct from a fast, copy-on-write clone.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CopyVm.run("https://xenserver", "root", password, "db-01", "Shared NFS", "sdk-example-copy");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String vmName, String srName, String copyName) throws Exception {
        Connection conn = connect(url, user, password);
        // A full copy needs a halted source; it places an independent set of disks on the chosen SR.
        VM source = vmByName(conn, vmName);
        SR sr = srByName(conn, srName, false);
        System.out.println("Copying '" + source.getNameLabel(conn) + "' to SR: " + sr.getNameLabel(conn));

        // VM.copy (like VM.clone) requires a Halted source (VM_BAD_POWER_STATE otherwise).
        boolean wasRunning = source.getPowerState(conn) == Types.VmPowerState.RUNNING;
        if (wasRunning) source.cleanShutdown(conn);

        VM copy = source.copy(conn, copyName, sr);
        System.out.println("Copied VM:     " + copy.getUuid(conn));
        System.out.println("Copy has " + copy.getVBDs(conn).size()
                + " VBD(s), is_a_template = " + copy.getIsATemplate(conn));

        if (wasRunning) source.start(conn, false, true);

        // Tidy up: destroy the copy and its disks, leaving the source VM intact.
        destroyVmAndDisks(conn, copy);
        System.out.println("Cleaned up the copied VM (left the source intact).");
        System.out.println("OK: copy-vm");
        Session.logout(conn);
    }
}
