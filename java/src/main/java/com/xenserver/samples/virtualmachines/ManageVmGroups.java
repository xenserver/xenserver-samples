package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VMGroup;

import java.util.LinkedHashSet;
import java.util.Set;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVmGroups {
    private ManageVmGroups() {
    }

    /**
     * Manage VM groups.
     *
     * <p>Create an anti-affinity VM group, put a VM in it, read the membership back from the group side,
     * then take the VM out again and delete the group.
     */
    public static void run(String url, String user, String password,
            String vmName, String groupName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);

        // anti_affinity asks the pool to keep the group's members on different hosts.
        VMGroup.Record spec = new VMGroup.Record();
        spec.nameLabel = groupName;
        spec.nameDescription = "Anti-affinity group created by the SDK example";
        spec.placement = Types.PlacementPolicy.ANTI_AFFINITY;
        VMGroup group = VMGroup.create(conn, spec);
        System.out.println("Created group:  " + group.getUuid(conn));

        // Membership is written from the VM side...
        Set<VMGroup> groups = new LinkedHashSet<>();
        groups.add(group);
        vm.setGroups(conn, groups);

        // ...and read back from the group side, which is the half that is easy to get wrong.
        Set<VM> members = group.getVMs(conn);
        System.out.println("Group members:  " + members.size());
        for (VM m : members) {
            System.out.println("  " + m.getNameLabel(conn));
        }

        // VM_group.destroy already clears the group from every member VM's groups field - no need to
        // remove membership ourselves first.
        group.destroy(conn);
        System.out.println("OK: manage-vm-groups");
        Session.logout(conn);
    }
}
