package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.HostMetrics;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VMMetrics;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ReadMetrics {
    private ReadMetrics() {
    }

    /**
     * Read host &amp; VM metrics.
     *
     * <p>Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ReadMetrics.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        final long MiB = 1024L * 1024;
        Connection conn = connect(url, user, password);
        Map.Entry<Host, Host.Record> he = Host.getAllRecords(conn).entrySet().iterator().next();
        HostMetrics hm = he.getKey().getMetrics(conn);
        System.out.println("Host " + he.getValue().nameLabel + ": "
                + hm.getMemoryTotal(conn) / MiB + " MiB total, "
                + he.getKey().computeFreeMemory(conn) / MiB + " MiB free, "
                + "live = " + hm.getLive(conn));

        VM vm = null;
        for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
            VM.Record r = e.getValue();
            if (!r.isATemplate && !r.isControlDomain && r.powerState == Types.VmPowerState.RUNNING) {
                vm = e.getKey();
                break;
            }
        }
        VMMetrics vmm = vm.getMetrics(conn);
        System.out.println("VM " + vm.getNameLabel(conn) + ": "
                + vmm.getVCPUsNumber(conn) + " vCPU(s), "
                + vmm.getMemoryActual(conn) / MiB + " MiB");
        System.out.println("OK: read-metrics");
        Session.logout(conn);
    }
}
