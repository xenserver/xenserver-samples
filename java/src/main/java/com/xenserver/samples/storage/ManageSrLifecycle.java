package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageSrLifecycle {
    private ManageSrLifecycle() {
    }

    /**
     * Detach, reattach and forget storage.
     *
     * <p>Take a storage repository offline and bring it back: disconnect it from every host, reconnect and
     * rescan it, then disconnect it once more and forget it for good.
     */
    public static void run(String url, String user, String password,
            String nfsServer, String nfsPath) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // There is no "detach" call on an SR. A shared SR is joined to each host by one PBD - a
            // physical block device - and detaching the SR means unplugging every one of them. That is
            // why an SR can be attached on some hosts and not others, and why a repair action exists at
            // all: it plugs back the PBDs that are missing.
            Host host = Host.getAll(conn).iterator().next();
            Map<String, String> deviceConfig = new java.util.HashMap<>();
            deviceConfig.put("server", nfsServer);
            deviceConfig.put("serverpath", nfsPath);
            deviceConfig.put("nfsversion", "3");
            SR sr = SR.create(conn, host, deviceConfig, 0L,
                "sdk-example-lifecycle", "SR used by the SDK lifecycle example",
                "nfs", "user", true, new java.util.HashMap<>());

            java.util.List<PBD> pbds = new java.util.ArrayList<>(sr.getPBDs(conn));
            System.out.printf("%s: connected on %d of %d host(s)%n",
                sr.getNameLabel(conn), attachedPbds(conn, pbds), pbds.size());

            for (PBD pbd : pbds) pbd.unplug(conn);
            System.out.printf("  detached:   connected on %d host(s)%n", attachedPbds(conn, pbds));

            // Plugging them back is exactly what a repair does.
            for (PBD pbd : pbds) pbd.plug(conn);
            System.out.printf("  reattached: connected on %d host(s)%n", attachedPbds(conn, pbds));

            sr.scan(conn);
            System.out.printf("  rescanned:  %d disk(s)%n", sr.getVDIs(conn).size());

            // Forgetting drops the pool's record of the SR but leaves the storage itself untouched, so
            // the same export can be introduced again later. Detach before forgetting: a connected SR
            // is still in use.
            for (PBD pbd : pbds) pbd.unplug(conn);
            sr.forget(conn);
            System.out.println("  forgotten");
            System.out.println("OK: manage-sr-lifecycle");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * How many of these connections are currently live.
     */
    private static int attachedPbds(Connection conn, java.util.List<PBD> pbds) throws Exception {
        int live = 0;
        for (PBD pbd : pbds) if (pbd.getCurrentlyAttached(conn)) live++;
        return live;
    }
}
