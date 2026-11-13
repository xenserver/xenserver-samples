package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.PVSCacheStorage;
import com.xensource.xenapi.PVSProxy;
import com.xensource.xenapi.PVSServer;
import com.xensource.xenapi.PVSSite;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class PvsAccelerator {
    private PvsAccelerator() {
    }

    /**
     * PVS Accelerator inventory.
     *
     * <p>Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host,
     * size, storage), its PVS servers (addresses and streaming port range), and which VMs are accelerated
     * versus the whole pool.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Map<PVSSite, PVSSite.Record> sites = PVSSite.getAllRecords(conn);
            if (sites.isEmpty()) System.out.println("No PVS Accelerator sites are configured.");
            for (PVSSite.Record site : sites.values()) {
                System.out.println("Site: " + site.nameLabel);
                for (PVSCacheStorage cs : site.cacheStorage) {
                    PVSCacheStorage.Record r = cs.getRecord(conn);
                    System.out.printf("  cache:  %s  %d GiB on %s%n",
                        r.host.getNameLabel(conn), r.size / (1024L * 1024 * 1024), r.SR.getNameLabel(conn));
                }
                for (PVSServer server : site.servers) {
                    PVSServer.Record r = server.getRecord(conn);
                    System.out.printf("  server: %s  ports %d-%d%n", String.join(", ", r.addresses), r.firstPort, r.lastPort);
                }
                // Which VMs are accelerated: walk each proxy to its VIF to its VM.
                java.util.Set<String> accelerated = new java.util.HashSet<>();
                for (PVSProxy proxy : site.proxies) {
                    VIF vif = proxy.getRecord(conn).VIF;
                    accelerated.add(vif.getRecord(conn).VM.toWireString());
                }
                int total = 0, count = 0;
                for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                    VM.Record v = e.getValue();
                    if (v.isControlDomain || v.isATemplate || v.isASnapshot) continue;
                    total++;
                    if (accelerated.contains(e.getKey().toWireString())) count++;
                }
                System.out.printf("  %d of %d VM(s) accelerated%n", count, total);
            }
            System.out.println("OK: pvs-accelerator");
        } finally {
            Session.logout(conn);
        }
    }
}
