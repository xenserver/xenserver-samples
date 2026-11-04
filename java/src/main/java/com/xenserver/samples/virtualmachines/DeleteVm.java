package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.Set;

import static com.xenserver.samples.Helpers.diskVdis;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class DeleteVm {
    private DeleteVm() {
    }

    /**
     * Delete a VM.
     *
     * <p>Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are
     * destroyed explicitly afterward.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * DeleteVm.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-delete");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        // Make a throwaway VM to delete. VM.destroy removes the VM but leaves its disks, so the
        // owned VDIs are destroyed explicitly afterward — exactly what XenCenter's Delete VM does.
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm);
        String uuid = vm.getUuid(conn);
        Set<VDI> vdis = diskVdis(conn, vm);
        System.out.println("Deleting VM " + uuid + " with " + vdis.size() + " disk(s)");

        vm.destroy(conn);
        for (VDI vdi : vdis) vdi.destroy(conn);

        boolean stillThere = false;
        for (VM.Record r : VM.getAllRecords(conn).values())
            if (uuid.equals(r.uuid)) { stillThere = true; break; }
        System.out.println("VM still present: " + stillThere);
        System.out.println("OK: delete-vm");
        Session.logout(conn);
    }
}
