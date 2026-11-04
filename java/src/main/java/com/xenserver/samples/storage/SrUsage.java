package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class SrUsage {
    private SrUsage() {
    }

    /**
     * Storage repository usage.
     *
     * <p>Report each storage repository's used and total capacity, and rescan one.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * SrUsage.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        java.util.List<SR.Record> srs = new java.util.ArrayList<>(SR.getAllRecords(conn).values());
        srs.sort(java.util.Comparator.comparing((SR.Record s) -> s.nameLabel));
        for (SR.Record sr : srs) {
            if (sr.physicalSize <= 0) continue; // skip ISO/DVD pseudo-SRs
            System.out.println("  " + sr.nameLabel + ": " + sr.physicalUtilisation / GiB
                    + " / " + sr.physicalSize / GiB + " GiB used");
        }
        // A rescan refreshes an SR's utilisation from its backend.
        SR scanMe = null;
        for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet())
            if (e.getValue().physicalSize > 0) { scanMe = e.getKey(); break; }
        scanMe.scan(conn);

        // Read caching keeps recently-read blocks in the host's memory. It is switched off per SR by
        // setting o_direct, which asks the storage layer to bypass the cache entirely.
        scanMe.removeFromOtherConfig(conn, "o_direct");
        scanMe.addToOtherConfig(conn, "o_direct", "true");
        System.out.println("  read caching on " + scanMe.getNameLabel(conn) + ": "
                + ("true".equals(scanMe.getOtherConfig(conn).get("o_direct")) ? "off" : "on"));
        scanMe.removeFromOtherConfig(conn, "o_direct");
        System.out.println("OK: sr-usage");
        Session.logout(conn);
    }
}
