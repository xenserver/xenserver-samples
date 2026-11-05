package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureDynamicMemory {
    private ConfigureDynamicMemory() {
    }

    /**
     * Configure dynamic memory.
     *
     * <p>Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see
     * the ordering rule the four bounds must obey enforced.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureDynamicMemory.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = null;
            VM.Record before = null;
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record v = e.getValue();
                if (!v.isATemplate && !v.isControlDomain && !v.isASnapshot
                        && v.powerState == Types.VmPowerState.HALTED) {
                    vm = e.getKey(); before = v; break;
                }
            }
            if (vm == null) throw new Exception("no halted VM");
            System.out.printf("%s: static %s-%s, dynamic %s-%s%n", before.nameLabel,
                    gib(before.memoryStaticMin), gib(before.memoryStaticMax),
                    gib(before.memoryDynamicMin), gib(before.memoryDynamicMax));

            // Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
            // static maximum for every supported guest (lower can make it unstable), and never below the static
            // floor, which is the least the guest can boot in.
            long floor = Math.max(before.memoryStaticMin, before.memoryStaticMax * 3 / 4);
            long ceiling = before.memoryStaticMax;
            vm.setMemoryDynamicRange(conn, floor, ceiling);
            System.out.printf("  dynamic range now %s-%s%n",
                    gib(vm.getMemoryDynamicMin(conn)), gib(vm.getMemoryDynamicMax(conn)));

            // The ordering is enforced, not advisory: a range wider than the static bounds is refused
            // rather than quietly clamped.
            try {
                vm.setMemoryDynamicRange(conn, floor, ceiling * 2);
                System.out.println("  ERROR: an out-of-range maximum was accepted");
            } catch (Types.XenAPIException e) {
                System.out.println("  refused a dynamic_max above static_max: " + e.shortDescription);
            }

            vm.setMemoryDynamicRange(conn, before.memoryDynamicMin, before.memoryDynamicMax);
            System.out.println("OK: configure-dynamic-memory");
        } finally {
            Session.logout(conn);
        }
    }

    private static String gib(long bytes) {
        return String.format("%.1f GiB", bytes / (1024.0 * 1024 * 1024));
    }
}
