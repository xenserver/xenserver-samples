package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Cluster;
import com.xensource.xenapi.ClusterHost;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.PIF;
import com.xensource.xenapi.Session;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureClustering {
    private ConfigureClustering() {
    }

    /**
     * Configure clustering.
     *
     * <p>Enable the clustering layer that shared block storage needs for thin provisioning, then watch
     * quorum as a host leaves the cluster and rejoins it.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureClustering.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Clustering is what shared block storage needs before GFS2 thin provisioning. Run it over a
            // network every host is on - the management network - since corosync is latency-sensitive
            // and a cluster that loses quorum takes its GFS2 storage offline with it.
            Map<PIF, PIF.Record> pifs = PIF.getAllRecords(conn);
            Network network = null;
            for (PIF.Record r : pifs.values()) {
                if (r.management) { network = r.network; break; }
            }
            Map<PIF, Boolean> was = new HashMap<>();
            for (Map.Entry<PIF, PIF.Record> e : pifs.entrySet()) {
                if (e.getValue().network.equals(network)) was.put(e.getKey(), e.getValue().disallowUnplug);
            }

            Set<Cluster> existing = Cluster.getAll(conn);
            Cluster cluster;
            if (!existing.isEmpty()) {
                cluster = existing.iterator().next();
            } else {
                // Corosync must not lose its network, so each host's PIF on it has to refuse unplugging
                // first: Cluster.poolCreate fails PIF_ALLOWS_UNPLUG otherwise. was remembers the settings.
                for (PIF pif : was.keySet()) pif.setDisallowUnplug(conn, true);
                // token_timeout is in seconds (the API's default is 20.0, coefficient 1.0): XS9 refuses
                // 20000 as "too large" - it is not milliseconds.
                cluster = Cluster.poolCreate(conn, network, "corosync", 20.0, 1.0);
            }

            System.out.println("Stack:      " + cluster.getClusterStack(conn));
            System.out.println("Quorate:    " + cluster.getIsQuorate(conn)
                    + " (" + cluster.getLiveHosts(conn) + "/" + cluster.getQuorum(conn) + " needed)");

            // Taking a host out is what a management-interface change does; it can cost quorum.
            ClusterHost member = ClusterHost.getAll(conn).iterator().next();
            member.disable(conn);
            System.out.println("One member out, quorate: " + cluster.getIsQuorate(conn));

            member.enable(conn);
            cluster.poolResync(conn);
            System.out.println("Resynced,   quorate: " + cluster.getIsQuorate(conn));

            // Tidy up a cluster this example created (one that was already there stays), and the PIF
            // settings.
            if (existing.isEmpty()) {
                cluster.poolDestroy(conn);
                for (Map.Entry<PIF, Boolean> e : was.entrySet()) e.getKey().setDisallowUnplug(conn, e.getValue());
                System.out.println("Cluster removed again.");
            }

            System.out.println("OK: configure-clustering");
        } finally {
            Session.logout(conn);
        }
    }
}
