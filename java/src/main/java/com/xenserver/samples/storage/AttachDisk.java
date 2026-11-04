package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class AttachDisk {
    private AttachDisk() {
    }

    /**
     * Attach a new disk.
     *
     * <p>Create a fresh virtual disk on a storage repository and attach it to a VM.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * AttachDisk.run("https://xenserver", "root", password, "Rocky Linux 8", "Shared NFS", "sdk-example-attachdisk");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String srName, String newVmName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm);
        SR sr = srByName(conn, srName, false);

        // Create a fresh VDI on the SR and attach it as a new VBD (a new virtual disk).
        VDI.Record vdiRec = new VDI.Record();
        vdiRec.nameLabel = "sdk-example-data-disk";
        vdiRec.SR = sr;
        vdiRec.virtualSize = 8 * GiB;
        vdiRec.type = Types.VdiType.USER;
        vdiRec.sharable = false;
        vdiRec.readOnly = false;
        vdiRec.otherConfig = new java.util.HashMap<>();
        VDI vdi = VDI.create(conn, vdiRec);

        String device = vm.getAllowedVBDDevices(conn).iterator().next();
        VBD.Record vbdRec = new VBD.Record();
        vbdRec.VM = vm;
        vbdRec.VDI = vdi;
        vbdRec.userdevice = device;
        vbdRec.bootable = false;
        vbdRec.mode = Types.VbdMode.RW;
        vbdRec.type = Types.VbdType.DISK;
        vbdRec.empty = false;
        vbdRec.otherConfig = new java.util.HashMap<>();
        vbdRec.qosAlgorithmType = "";
        vbdRec.qosAlgorithmParams = new java.util.HashMap<>();
        VBD.create(conn, vbdRec);
        System.out.println("Attached an 8 GiB disk on " + sr.getNameLabel(conn) + " as device " + device);
        System.out.println("VM now has " + vm.getVBDs(conn).size() + " VBD(s)");

        // Tidy up: the VM and both the disk it was provisioned with and the one just attached.
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: attach-disk");
        Session.logout(conn);
    }
}
