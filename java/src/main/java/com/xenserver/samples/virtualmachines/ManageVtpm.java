package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VTPM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVtpm {
    private ManageVtpm() {
    }

    /**
     * Manage a virtual TPM.
     *
     * <p>Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one,
     * and only while it is halted.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageVtpm.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // vTPM is not supported for a BIOS-mode VM, only a UEFI one (HVM_boot_params["firmware"]
            // == "uefi"), so pick one of those rather than any halted VM.
            VM vm = null;
            VM.Record record = null;
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record v = e.getValue();
                if (!v.isATemplate && !v.isControlDomain && !v.isASnapshot
                        && v.powerState == Types.VmPowerState.HALTED && v.VTPMs.isEmpty()
                        && "uefi".equals(v.HVMBootParams.get("firmware"))) {
                    vm = e.getKey(); record = v; break;
                }
            }
            if (vm == null) throw new Exception("no halted UEFI VM without a vTPM already attached was found");
            System.out.println("Attaching a vTPM to " + record.nameLabel);

            // isUnique=false: the vTPM may be copied along with the VM. A VM may have at most one, and
            // it can only be attached while Halted — the device is presented at boot.
            VTPM vtpm = VTPM.create(conn, vm, false);
            VTPM.Record vtpmRecord = vtpm.getRecord(conn);
            System.out.println("  persistence backend: " + vtpmRecord.persistenceBackend);
            System.out.println("  unique to this VM:   " + vtpmRecord.isUnique);
            System.out.println("  VM now has " + vm.getVTPMs(conn).size() + " vTPM(s)");

            // The VM advertises whether another can be added; once it has one, it cannot.
            System.out.println("  can add another:     "
                + vm.getAllowedOperations(conn).contains(Types.VmOperations.CREATE_VTPM));

            vtpm.destroy(conn);
            System.out.println("  after removal:       " + vm.getVTPMs(conn).size() + " vTPM(s)");
            System.out.println("OK: manage-vtpm");
        } finally {
            Session.logout(conn);
        }
    }
}
