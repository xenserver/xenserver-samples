package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.SM;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ReclaimSpace {
    private ReclaimSpace() {
    }

    /**
     * Reclaim freed space on a thin SR.
     *
     * <p>Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a
     * trim-capable SR, pick a host with a live connection to it, and run the trim operation.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ReclaimSpace.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        try {
            // Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
            java.util.Set<String> trimTypes = new java.util.HashSet<>();
            for (SM.Record sm : SM.getAllRecords(conn).values())
                if (sm.features.containsKey("SR_TRIM")) trimTypes.add(sm.type);
            SR sr = null;
            SR.Record srRecord = null;
            for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet())
                if (e.getValue().physicalSize > 0 && trimTypes.contains(e.getValue().type)) {
                    sr = e.getKey();
                    srRecord = e.getValue();
                    break;
                }
            // A host with a currently-attached PBD can reach the SR to run the plugin.
            Host host = null;
            for (PBD pbd : srRecord.PBDs) {
                PBD.Record pr = pbd.getRecord(conn);
                if (pr.currentlyAttached) { host = pr.host; break; }
            }

            System.out.println("  " + srRecord.nameLabel + ": " + srRecord.physicalUtilisation / GiB
                    + " / " + srRecord.physicalSize / GiB + " GiB used");

            java.util.Map<String, String> pargs = new java.util.HashMap<>();
            pargs.put("sr_uuid", srRecord.uuid);
            String result = host.callPlugin(conn, "trim", "do_trim", pargs);
            System.out.println("  reclaimed freed space on " + srRecord.nameLabel + ": " + result);
            // Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
            if (!"true".equalsIgnoreCase(result.trim()))
                throw new IllegalStateException("trim plugin returned '" + result + "'");

            // Rescan to refresh utilisation from the backend, the same way SrUsage does, before reporting it.
            sr.scan(conn);
            long usedAfter = sr.getRecord(conn).physicalUtilisation;
            System.out.println("  " + srRecord.nameLabel + ": " + usedAfter / GiB
                    + " / " + srRecord.physicalSize / GiB + " GiB used");
            System.out.println("OK: reclaim-space");
        } finally {
            Session.logout(conn);
        }
    }
}
