package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.Helpers.detachAndForgetSr;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateIsoSr {
    private CreateIsoSr() {
    }

    /**
     * Create an ISO library SR.
     *
     * <p>Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so
     * the images are available as installation media.
     *
     * <p>Connect an ISO-library SR to a file share of ISO images (here an NFS export, location
     * "server:/path").
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateIsoSr.run("https://xenserver", "root", password, "192.0.2.10:/isos");
     * }</pre>
     */
    public static void run(String url, String user, String password, String location) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Host host = Host.getAllRecords(conn).keySet().iterator().next();
            Map<String, String> dc = new java.util.HashMap<>();
            dc.put("location", location);
            dc.put("type", "nfs_iso");
            SR sr = SR.create(conn, host, dc, 0L, "sdk-example-iso", "ISO library created by the SDK example",
                "iso", "iso", true, new java.util.HashMap<>());
            System.out.println("Created ISO SR: " + sr.getUuid(conn));
            detachAndForgetSr(conn, sr);
            System.out.println("OK: create-iso-sr");
        } finally {
            Session.logout(conn);
        }
    }
}
