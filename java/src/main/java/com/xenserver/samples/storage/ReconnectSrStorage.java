package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static com.xenserver.samples.Helpers.detachAndForgetSr;
import static com.xenserver.samples.PoolConnection.connect;

public final class ReconnectSrStorage {
    private ReconnectSrStorage() {
    }

    /**
     * Point an SR at moved storage.
     *
     * <p>When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an
     * SR cannot be edited, so unplug each one, recreate it with the new settings and plug it back.
     *
     * <p>Each host reaches an SR through a PBD, whose device_config (server, path, target, ...) says where
     * the storage is. A PBD's device_config is fixed when it is created, so changing it means unplugging the
     * PBD, destroying it, and creating and plugging a new one with the updated settings, host by host. The
     * SR and its disks are untouched throughout. Every PBD has to be unplugged first, which needs every VM
     * using the SR to be shut down. This example creates an NFS SR on nfsServer:nfsPath to work on, and
     * forgets it again at the end; a null newNfsServer reconnects the SR to the same storage.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ReconnectSrStorage.run("https://xenserver", "root", password, "192.0.2.10", "/export/spare", "192.0.2.11");
     * }</pre>
     */
    public static void run(String url, String user, String password, String nfsServer, String nfsPath,
                           String newNfsServer) throws Exception {
        Connection conn = connect(url, user, password);
        String newServer = newNfsServer != null ? newNfsServer : nfsServer;

        Host host = Host.getAll(conn).iterator().next();
        Map<String, String> deviceConfig = new HashMap<>();
        deviceConfig.put("server", nfsServer);
        deviceConfig.put("serverpath", nfsPath);
        deviceConfig.put("nfsversion", "3");
        SR sr = SR.create(conn, host, deviceConfig, 0L, "sdk-example-moved-storage",
            "SR used by the SDK reconnect example", "nfs", "user", true, new HashMap<>());
        try {
            List<PBD> pbds = new ArrayList<>(sr.getPBDs(conn));
            for (PBD pbd : pbds) pbd.unplug(conn);

            for (PBD pbd : pbds) {
                PBD.Record record = pbd.getRecord(conn);
                Map<String, String> moved = new HashMap<>(record.deviceConfig);
                moved.put("server", newServer);
                pbd.destroy(conn);
                PBD.Record replacement = new PBD.Record();
                replacement.host = record.host;
                replacement.SR = sr;
                replacement.deviceConfig = moved;
                replacement.otherConfig = new HashMap<>();
                PBD.create(conn, replacement).plug(conn);
                System.out.printf("%s: now reaches %s:%s%n", record.host.getNameLabel(conn),
                    moved.get("server"), moved.get("serverpath"));
            }
        } finally {
            // Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
            detachAndForgetSr(conn, sr);
        }
        System.out.println("OK: reconnect-sr-storage");
        Session.logout(conn);
    }
}
