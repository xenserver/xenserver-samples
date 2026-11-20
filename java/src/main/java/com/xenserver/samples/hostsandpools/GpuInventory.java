package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.GPUGroup;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VGPUType;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class GpuInventory {
    private GpuInventory() {
    }

    /**
     * GPU inventory.
     *
     * <p>Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * GpuInventory.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Map<GPUGroup, GPUGroup.Record> groups = GPUGroup.getAllRecords(conn);
        System.out.println("GPU groups (" + groups.size() + "):");
        for (GPUGroup.Record group : groups.values()) {
            StringBuilder types = new StringBuilder();
            for (VGPUType t : group.supportedVGPUTypes) {
                if (types.length() > 0) types.append(", ");
                types.append(t.getModelName(conn));
            }
            System.out.println("  - " + group.nameLabel + ": " + group.PGPUs.size()
                    + " pGPU(s), vGPU types: " + types);
        }
        // How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU
        // full before using the next, breadth-first spreads them out.
        GPUGroup groupRef = groups.keySet().iterator().next();
        Types.AllocationAlgorithm before = groupRef.getAllocationAlgorithm(conn);
        groupRef.setAllocationAlgorithm(conn, Types.AllocationAlgorithm.BREADTH_FIRST);
        System.out.println("Allocation:      " + before + " -> " + groupRef.getAllocationAlgorithm(conn));
        groupRef.setAllocationAlgorithm(conn, before);
        System.out.println("OK: gpu-inventory");
        Session.logout(conn);
    }
}
