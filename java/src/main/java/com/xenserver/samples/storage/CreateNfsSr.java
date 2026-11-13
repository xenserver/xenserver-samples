package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.Helpers.detachAndForgetSr;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateNfsSr {
    private CreateNfsSr() {
    }

    /**
     * Create an NFS SR.
     *
     * <p>Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and
     * forget it.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateNfsSr.run("https://xenserver", "root", password, "192.0.2.10", "/export/sdk", "sdk-example-nfs");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String nfsServer, String nfsPath, String srName) throws Exception {
        Connection conn = connect(url, user, password);
        Host host = Host.getAllRecords(conn).keySet().iterator().next();
        Map<String, String> deviceConfig = new java.util.HashMap<>();
        deviceConfig.put("server", nfsServer);
        deviceConfig.put("serverpath", nfsPath);
        deviceConfig.put("nfsversion", "3");

        SR sr = SR.create(conn, host, deviceConfig, 0L,
            srName, "NFS SR created by the SDK example",
            "nfs", "user", true, new java.util.HashMap<>());
        System.out.println("Created SR: " + sr.getUuid(conn));

        detachAndForgetSr(conn, sr);
        System.out.println("OK: create-nfs-sr");
        Session.logout(conn);
    }
}
