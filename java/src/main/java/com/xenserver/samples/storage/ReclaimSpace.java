package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.SM;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

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
        Connection conn = connect(url, user, password);
        try {
            // Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
            java.util.Set<String> trimTypes = new java.util.HashSet<>();
            for (SM.Record sm : SM.getAllRecords(conn).values())
                if (sm.features.containsKey("SR_TRIM")) trimTypes.add(sm.type);
            SR.Record sr = null;
            for (SR.Record r : SR.getAllRecords(conn).values())
                if (r.physicalSize > 0 && trimTypes.contains(r.type)) { sr = r; break; }
            // A host with a currently-attached PBD can reach the SR to run the plugin.
            Host host = null;
            for (PBD pbd : sr.PBDs) {
                PBD.Record pr = pbd.getRecord(conn);
                if (pr.currentlyAttached) { host = pr.host; break; }
            }
            java.util.Map<String, String> pargs = new java.util.HashMap<>();
            pargs.put("sr_uuid", sr.uuid);
            String result = host.callPlugin(conn, "trim", "do_trim", pargs);
            System.out.println("  reclaimed freed space on " + sr.nameLabel + ": " + result);
            // Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
            if (!"true".equalsIgnoreCase(result.trim()))
                throw new RuntimeException("trim plugin returned '" + result + "'");
            System.out.println("OK: reclaim-space");
        } finally {
            Session.logout(conn);
        }
    }
}
