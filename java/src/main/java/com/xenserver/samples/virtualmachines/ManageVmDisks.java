package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SM;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.HashMap;
import java.util.Map;

import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVmDisks {
    private ManageVmDisks() {
    }

    /**
     * Manage VM disks.
     *
     * <p>Deactivate a running VM's disk, resize it, reactivate it — the Activate/Deactivate and Resize
     * operations from the VM's Storage tab.
     *
     * <p>Not the VM's root/boot disk: a real VM's system disk is unpluggable=false (only a template's
     * non-system disks default to unpluggable), so VBD.unplug on it fails on a real host with
     * VBD_NOT_UNPLUGGABLE - and the VM has to be running in the first place, or unplug fails with
     * VM_BAD_POWER_STATE. Work on a data disk this example adds to its own throwaway VM instead, and
     * tidy up afterwards so the example is repeatable. No shrink: real SR backends refuse one
     * outright (SR_BACKEND_FAILURE_79), so this only ever grows.
     *
     * <p>Plugging and unplugging a disk on a running VM needs the guest's PV drivers
     * (VM_MISSING_PV_DRIVERS otherwise), so the VM is a throwaway copy of sourceVm, a VM with a guest OS
     * and PV drivers.
     */
    public static void run(String url, String user, String password,
            String sourceVm, String srName, String newVmName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        VM vm = copyOfGuest(conn, sourceVm, newVmName);
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);

        SR sr = srByName(conn, srName, false);
        VDI.Record vdiRec = new VDI.Record();
        vdiRec.nameLabel = "sdk-example-data-disk";
        vdiRec.SR = sr;
        vdiRec.virtualSize = 4 * GiB;
        vdiRec.type = Types.VdiType.USER;
        vdiRec.sharable = false;
        vdiRec.readOnly = false;
        vdiRec.otherConfig = new HashMap<>();
        VDI vdi = VDI.create(conn, vdiRec);

        VBD.Record vbdRec = new VBD.Record();
        vbdRec.VM = vm;
        vbdRec.VDI = vdi;
        vbdRec.userdevice = vm.getAllowedVBDDevices(conn).iterator().next();
        vbdRec.bootable = false;
        vbdRec.mode = Types.VbdMode.RW;
        vbdRec.type = Types.VbdType.DISK;
        vbdRec.empty = false;
        // A Java record sends every field, so say so explicitly: a VBD created with unpluggable=false
        // can't be hot-unplugged (VBD_NOT_UNPLUGGABLE). xapi's own default, when the field is left
        // out, is true.
        vbdRec.unpluggable = true;
        vbdRec.otherConfig = new HashMap<>();
        vbdRec.qosAlgorithmType = "";
        vbdRec.qosAlgorithmParams = new HashMap<>();
        VBD vbd = VBD.create(conn, vbdRec);
        vbd.plug(conn);
        System.out.println("Disk attached:  " + vbd.getCurrentlyAttached(conn));

        // Deactivate = VBD.unplug. The disk stays with the VM; it is just no longer live.
        vbd.unplug(conn);
        System.out.println("After unplug:   " + vbd.getCurrentlyAttached(conn));

        Long size = vdi.getVirtualSize(conn);
        vdi.resize(conn, size * 2);
        System.out.println("Resized:        " + size + " -> " + vdi.getVirtualSize(conn) + " bytes");

        vbd.plug(conn);
        System.out.println("After plug:     " + vbd.getCurrentlyAttached(conn));

        // Growing a disk that is attached and live is a DIFFERENT call, not a flag on the same one:
        // resizeOnline tells the storage layer the guest is using the disk while it grows. Only some
        // storage drivers can (none of a stock XenServer 9's do), and the rest refuse with
        // SR_OPERATION_NOT_SUPPORTED - so ask the SR's driver (its SM record's features) first.
        String srType = sr.getType(conn);
        Map<String, Long> features = new HashMap<>();
        for (SM.Record r : SM.getAllRecords(conn).values()) {
            if (srType.equals(r.type)) { features = r.features; break; }
        }
        if (features.containsKey("VDI_RESIZE_ONLINE")) {
            long grown = vdi.getVirtualSize(conn) + GiB;
            vdi.resizeOnline(conn, grown);
            System.out.println("Grown online:   " + vdi.getVirtualSize(conn) + " bytes");
        } else {
            System.out.println("Grown online:   not supported by " + srType
                    + " storage; unplug, resize, plug as above");
        }

        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: manage-vm-disks");
        Session.logout(conn);
    }
}
