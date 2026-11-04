package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.PVSCacheStorage;
import com.xensource.xenapi.PVSProxy;
import com.xensource.xenapi.PVSServer;
import com.xensource.xenapi.PVSSite;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigurePvsAccelerator {
    private ConfigurePvsAccelerator() {
    }

    /**
     * Configure PVS Accelerator.
     *
     * <p>Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS
     * server, put a read cache on each host's local storage, accelerate a VM by proxying its first NIC,
     * then forget the site — which cascades to everything hanging off it.
     *
     * <p>Build a PVS Accelerator site from nothing: a site, a PVS server, a read cache on each host, and
     * one accelerated VM (vmName). Then take it all down again.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigurePvsAccelerator.run("https://xenserver", "root", password, "db-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Check the VM first, before creating anything: it needs a NIC for the proxy to sit on. It
            // need not be running - a proxy on a halted VM just reports "stopped" until it starts.
            VM vm = vmByName(conn, vmName);
            java.util.List<VIF> vifs = new java.util.ArrayList<>(vm.getVIFs(conn));
            vifs.sort(java.util.Comparator.comparingInt(v -> {
                try {
                    return Integer.parseInt(v.getDevice(conn));
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            }));
            if (vifs.isEmpty()) throw new RuntimeException(vmName + " has no network interface to accelerate");
            // ... and one that no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT).
            for (PVSProxy.Record proxy : PVSProxy.getAllRecords(conn).values())
                if (proxy.VIF.equals(vifs.get(0)))
                    throw new RuntimeException(vmName + " is already accelerated by site '"
                            + proxy.site.getNameLabel(conn) + "'");

            PVSSite site = PVSSite.introduce(conn, "sdk-example-pvs", "Created by the SDK examples", "");
            PVSServer.introduce(conn, new java.util.HashSet<>(java.util.Arrays.asList("203.0.113.90")),
                6910L, 6930L, site);

            // The read cache must be on LOCAL storage. The point of the accelerator is to keep reads off
            // the network, so a cache on a shared SR would defeat it and the server rejects one.
            for (Host host : Host.getAll(conn)) {
                SR local = localSr(conn, host);
                if (local == null) continue;
                PVSCacheStorage.Record cache = new PVSCacheStorage.Record();
                cache.host = host;
                cache.SR = local;
                cache.site = site;
                cache.size = 10L * 1024 * 1024 * 1024;
                PVSCacheStorage.create(conn, cache);
            }

            // A proxy may only sit on the VM's LOWEST-numbered VIF, hence sorting by device above rather
            // than taking the first one — the set comes back unordered, so "the first one" means
            // nothing here.
            PVSProxy proxy = PVSProxy.create(conn, site, vifs.get(0));

            PVSSite.Record record = site.getRecord(conn);
            System.out.printf("Site '%s' with %d cache(s) and %d server(s)%n",
                record.nameLabel, record.cacheStorage.size(), record.servers.size());
            // "caching" means it is actually accelerating. A site with no cache storage reports
            // "initialised", and a proxy on a VM whose VIF is unplugged reports "stopped".
            System.out.printf("  %s: %s%n", vm.getNameLabel(conn), proxy.getStatus(conn));

            // Forgetting the site only cascades its cache storage - a running proxy or a server it still
            // has makes forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down
            // ourselves first, in the same order every real PVS teardown uses.
            proxy.destroy(conn);
            for (PVSServer server : site.getServers(conn)) server.forget(conn);
            site.forget(conn);
            System.out.println("OK: configure-pvs-accelerator");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * The host's own non-ISO storage, found through its PBDs.
     */
    private static SR localSr(Connection conn, Host host) throws Exception {
        for (PBD pbd : host.getPBDs(conn)) {
            SR sr = pbd.getSR(conn);
            SR.Record r = sr.getRecord(conn);
            if (!r.shared && !"iso".equals(r.contentType) && r.type != null && !r.type.equals("udev"))
                return sr;
        }
        return null;
    }
}
