package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VMSS;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class SnapshotSchedule {
    private SnapshotSchedule() {
    }

    /**
     * Snapshot schedule.
     *
     * <p>Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention
     * limit prune the oldest snapshot away.
     */
    public static void run(String url, String user, String password,
            String vmName, String scheduleName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);

        // retainedSnapshots is the interesting field: the schedule prunes to it every time it runs.
        VMSS.Record spec = new VMSS.Record();
        spec.nameLabel = scheduleName;
        spec.nameDescription = "Scheduled snapshots created by the SDK example";
        spec.enabled = true;
        spec.type = Types.VmssType.SNAPSHOT;
        spec.frequency = Types.VmssFrequency.DAILY;
        spec.retainedSnapshots = 2L;
        Map<String, String> when = new HashMap<>();
        when.put("hour", "2");
        when.put("min", "0");
        spec.schedule = when;
        VMSS vmss = VMSS.create(conn, spec);
        System.out.println("Created schedule: " + vmss.getUuid(conn));

        vm.setSnapshotSchedule(conn, vmss);
        System.out.println("Members:          " + vmss.getVMs(conn).size());

        // Run it three times against a retention of two: the oldest is pruned away. Compare against the
        // snapshots the VM already had, so only the schedule's own are counted (and tidied up below).
        Set<VM> before = vm.getSnapshots(conn);
        for (int i = 0; i < 3; i++) {
            vmss.snapshotNow(conn);
        }
        Set<VM> kept = new HashSet<>(vm.getSnapshots(conn));
        kept.removeAll(before);
        System.out.println("Snapshots kept:   " + kept.size() + " (retention 2)");

        // Tidy up: a schedule with VMs still on it cannot be destroyed (VMSS_HAS_VM), so take the VM off it
        // first. Destroying the schedule leaves the snapshots it took, so destroy those too, with their disks.
        vm.setSnapshotSchedule(conn, new VMSS("OpaqueRef:NULL"));
        vmss.destroy(conn);
        for (VM snapshot : kept) destroyVmAndDisks(conn, snapshot);
        System.out.println("OK: snapshot-schedule");
        Session.logout(conn);
    }
}
