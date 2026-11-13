package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.HostCrashdump;
import com.xensource.xenapi.Session;

import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageCrashDumps {
    private ManageCrashDumps() {
    }

    /**
     * Clear a host's crash dumps.
     *
     * <p>Find the crash dumps a host kept after a failure, report how big and how old they are, then
     * delete them to free the space.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // When a host crashes it writes a dump to its local disk and keeps it. They are large,
            // nothing cleans them up, and a host that has crashed more than once accumulates them - so
            // clearing them once support has what it needs is ordinary housekeeping. They belong to the
            // host that wrote them, so clear them a host at a time.
            Host host = null;
            Set<HostCrashdump> dumps = null;
            for (Host h : Host.getAll(conn)) {
                Set<HostCrashdump> d = h.getCrashdumps(conn);
                if (!d.isEmpty()) { host = h; dumps = d; break; }
            }
            if (host == null) {
                System.out.println("No crash dumps in this pool - nothing to clear.");
                System.out.println("OK: manage-crash-dumps");
                return;
            }

            System.out.printf("%s has %d crash dump(s)%n", host.getNameLabel(conn), dumps.size());
            long total = 0;
            java.text.SimpleDateFormat stamp = new java.text.SimpleDateFormat("yyyyMMdd'T'HH:mm:ss'Z'");
            stamp.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
            for (HostCrashdump dump : dumps) {
                HostCrashdump.Record record = dump.getRecord(conn);
                total += record.size;
                System.out.printf("  %s  %s%n", stamp.format(record.timestamp), mib(record.size));
            }
            System.out.printf("  %s in total%n", mib(total));

            // Deleting a dump frees the space on the host; the host itself is untouched.
            for (HostCrashdump dump : dumps) dump.destroy(conn);
            System.out.printf("  cleared:  %s now has %d%n",
                host.getNameLabel(conn), host.getCrashdumps(conn).size());

            System.out.println("OK: manage-crash-dumps");
        } finally {
            Session.logout(conn);
        }
    }

    private static String mib(long size) { return (size / (1024 * 1024)) + " MiB"; }
}
