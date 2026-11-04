package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.HashMap;
import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVmMedia {
    private ManageVmMedia() {
    }

    /**
     * Manage a VM's CD drive.
     *
     * <p>Add a DVD drive to a VM, insert an ISO from the library and eject it again.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageVmMedia.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = null;
            VM.Record record = null;
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record v = e.getValue();
                if (!v.isATemplate && !v.isControlDomain && !v.isASnapshot
                        && v.powerState == Types.VmPowerState.HALTED) {
                    vm = e.getKey(); record = v; break;
                }
            }
            if (vm == null) throw new Exception("no halted VM");
            System.out.println("Adding a DVD drive to " + record.nameLabel);

            // A CD drive is a VBD like any other, distinguished by type=CD; the media is whichever VDI it
            // points at, and an empty drive points at none.
            String device = vm.getAllowedVBDDevices(conn).iterator().next();
            VBD.Record spec = new VBD.Record();
            spec.VM = vm;
            spec.VDI = new VDI("OpaqueRef:NULL");
            spec.userdevice = device;
            spec.bootable = false;
            spec.mode = Types.VbdMode.RO;
            spec.type = Types.VbdType.CD;
            spec.empty = true;
            spec.unpluggable = true;
            spec.otherConfig = new HashMap<String, String>();
            spec.qosAlgorithmType = "";
            spec.qosAlgorithmParams = new HashMap<String, String>();
            VBD drive = VBD.create(conn, spec);
            System.out.println("  drive " + device + " is empty: " + drive.getEmpty(conn));

            // The ISO library is an SR of content type "iso"; its VDIs are the available images.
            SR isoSr = null;
            for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet())
                if ("iso".equals(e.getValue().contentType) && !"udev".equals(e.getValue().type)) {
                    isoSr = e.getKey(); break;
                }
            if (isoSr == null) throw new Exception("no ISO library");
            java.util.List<VDI> images = new java.util.ArrayList<VDI>(isoSr.getVDIs(conn));
            java.util.Map<VDI, String> names = new HashMap<VDI, String>();
            for (VDI image : images) names.put(image, image.getNameLabel(conn));
            images.sort(java.util.Comparator.comparing(names::get));
            VDI iso = images.get(0);
            System.out.println("  inserting " + names.get(iso));
            drive.insert(conn, iso);
            System.out.println("  drive now holds " + drive.getVDI(conn).getNameLabel(conn)
                    + " (empty=" + drive.getEmpty(conn) + ")");

            drive.eject(conn);
            System.out.println("  after eject, empty=" + drive.getEmpty(conn));

            drive.destroy(conn);
            System.out.println("OK: manage-vm-media");
        } finally {
            Session.logout(conn);
        }
    }
}
