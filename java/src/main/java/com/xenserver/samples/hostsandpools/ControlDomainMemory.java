package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.PoolConnection.connect;

public final class ControlDomainMemory {
    private ControlDomainMemory() {
    }

    /**
     * Change control domain memory.
     *
     * <p>Read and change a host's control domain (dom0) memory, then put it back. One setter pins the
     * static and dynamic bounds together, because dom0 does not balloon.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ControlDomainMemory.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Host host = Host.getAll(conn).iterator().next();
            VM dom0 = null;
            for (VM vm : host.getResidentVMs(conn))
                if (vm.getIsControlDomain(conn)) { dom0 = vm; break; }
            if (dom0 == null) throw new Exception("the host reports no control domain");

            long original = dom0.getMemoryDynamicMin(conn);
            System.out.printf("%s dom0: %.1f GiB%n", host.getNameLabel(conn),
                original / (double) (1024L * 1024 * 1024));

            // One setter, not a range: dom0 does not balloon, so setMemory pins the static and dynamic
            // bounds and the target together. The new size takes effect at the next reboot, so change
            // it with the host in maintenance mode — the API itself does not stop you.
            dom0.setMemory(conn, original + 1024L * 1024 * 1024);
            VM.Record record = dom0.getRecord(conn);
            System.out.printf("  now %.1f GiB (static %d-%d, dynamic %d-%d)%n",
                record.memoryDynamicMin / (double) (1024L * 1024 * 1024),
                record.memoryStaticMin, record.memoryStaticMax,
                record.memoryDynamicMin, record.memoryDynamicMax);

            dom0.setMemory(conn, original);   // leave the pool as we found it
            System.out.println("OK: control-domain-memory");
        } finally {
            Session.logout(conn);
        }
    }
}
