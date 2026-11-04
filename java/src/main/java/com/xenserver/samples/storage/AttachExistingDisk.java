package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class AttachExistingDisk {
    private AttachExistingDisk() {
    }

    /**
     * Attach an existing disk to another VM.
     *
     * <p>Move a disk between VMs by detaching and re-attaching it, without copying the data.
     */
    public static void run(String url, String user, String password) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        try {
            // A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk
            // between VMs is removing one VBD and creating another - no copying, and the data stays
            // exactly where it is.
            java.util.List<VM> halted = new java.util.ArrayList<>();
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record r = e.getValue();
                if (!r.isATemplate && !r.isControlDomain && !r.isASnapshot
                        && r.powerState == Types.VmPowerState.HALTED)
                    halted.add(e.getKey());
            }

            SR sr = null;
            for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet()) {
                SR.Record r = e.getValue();
                if (r.shared && !"iso".equals(r.contentType)
                        && r.type != null && !r.type.equals("iso") && !r.type.equals("udev")) {
                    sr = e.getKey(); break;
                }
            }

            VDI.Record vdiRecord = new VDI.Record();
            vdiRecord.nameLabel = "sdk-example-portable-disk";
            vdiRecord.SR = sr;
            vdiRecord.virtualSize = 4 * GiB;
            vdiRecord.type = Types.VdiType.USER;
            vdiRecord.sharable = false;
            vdiRecord.readOnly = false;
            vdiRecord.otherConfig = new java.util.HashMap<>();
            VDI vdi = VDI.create(conn, vdiRecord);
            System.out.printf("Disk %s created on %s%n", vdi.getNameLabel(conn), sr.getNameLabel(conn));

            VBD vbd = attachVdi(conn, halted.get(0), vdi);
            System.out.println("  attached to " + halted.get(0).getNameLabel(conn));

            // Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
            vbd.destroy(conn);
            System.out.printf("  detached:   the disk still exists (%d bytes)%n", vdi.getVirtualSize(conn));

            attachVdi(conn, halted.get(1), vdi);
            System.out.println("  attached to " + halted.get(1).getNameLabel(conn));
            System.out.printf("  the disk is on %d VM(s)%n", vdi.getVBDs(conn).size());

            for (VBD b : vdi.getVBDs(conn)) b.destroy(conn);
            vdi.destroy(conn);
            System.out.println("OK: attach-existing-disk");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Join an existing disk to a VM on its next free device slot.
     */
    private static VBD attachVdi(Connection conn, VM vm, VDI vdi) throws Exception {
        VBD.Record record = new VBD.Record();
        record.VM = vm;
        record.VDI = vdi;
        record.userdevice = vm.getAllowedVBDDevices(conn).iterator().next();
        record.bootable = false;
        record.mode = Types.VbdMode.RW;
        record.type = Types.VbdType.DISK;
        record.empty = false;
        record.otherConfig = new java.util.HashMap<>();
        record.qosAlgorithmType = "";
        record.qosAlgorithmParams = new java.util.HashMap<>();
        return VBD.create(conn, record);
    }
}
