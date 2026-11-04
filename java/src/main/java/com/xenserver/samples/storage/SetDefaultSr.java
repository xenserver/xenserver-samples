package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class SetDefaultSr {
    private SetDefaultSr() {
    }

    /**
     * Set the pool's default storage.
     *
     * <p>Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by
     * default, then put the original choice back.
     */
    public static void run(String url, String user, String password,
            String nfsServer, String nfsPath) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Pool pool = Pool.getAll(conn).iterator().next();

            // Capture all three separately. New disks land on the default SR, a suspended VM's memory
            // image goes to the suspend-image SR and host crash dumps to the crash-dump SR. They are
            // usually the same storage but need not be, and a pool that has never suspended or crashed
            // anything can legitimately leave the latter two unset - so restoring all three from the
            // default would quietly invent settings that were not there.
            SR before = pool.getDefaultSR(conn);
            SR beforeSuspend = pool.getSuspendImageSR(conn);
            SR beforeCrash = pool.getCrashDumpSR(conn);
            System.out.println("default storage:  " + srLabel(conn, before));
            System.out.println("  suspend images: " + srLabel(conn, beforeSuspend));
            System.out.println("  crash dumps:    " + srLabel(conn, beforeCrash));

            // Somewhere to switch to. A pool default has to be reachable from every host, so it is a
            // shared SR; a local one would strand any VM whose disk landed on the wrong host.
            Map<String, String> deviceConfig = new java.util.HashMap<>();
            deviceConfig.put("server", nfsServer);
            deviceConfig.put("serverpath", nfsPath);
            deviceConfig.put("nfsversion", "3");
            SR sr = SR.create(conn, Host.getAll(conn).iterator().next(), deviceConfig, 0L,
                "sdk-example-default", "SR used by the SDK default-storage example",
                "nfs", "user", true, new java.util.HashMap<>());

            pool.setDefaultSR(conn, sr);
            pool.setSuspendImageSR(conn, sr);
            pool.setCrashDumpSR(conn, sr);
            System.out.println("  switched to:    " + srLabel(conn, pool.getDefaultSR(conn)));

            // Restore the original choice before tidying up: an SR that is still the pool default is
            // the awkward one to remove.
            pool.setDefaultSR(conn, before);
            pool.setSuspendImageSR(conn, beforeSuspend);
            pool.setCrashDumpSR(conn, beforeCrash);
            for (PBD pbd : sr.getPBDs(conn)) pbd.unplug(conn);
            sr.forget(conn);
            System.out.println("  restored to:    " + srLabel(conn, pool.getDefaultSR(conn)));
            System.out.println("OK: set-default-sr");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * An SR's name, tolerating the null reference an unset pool field holds.
     */
    private static String srLabel(Connection conn, SR sr) throws Exception {
        if (sr == null || sr.toWireString() == null || sr.toWireString().equals("OpaqueRef:NULL"))
            return "(none)";
        return sr.getNameLabel(conn);
    }
}
