package com.xenserver.samples.networking;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class ListNetworks {
    private ListNetworks() {
    }

    /**
     * List networks.
     *
     * <p>Enumerate the pool's networks with their physical and virtual interface counts.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ListNetworks.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        java.util.List<Network.Record> nets = new java.util.ArrayList<>(Network.getAllRecords(conn).values());
        nets.sort(java.util.Comparator.comparing((Network.Record n) -> n.nameLabel));
        System.out.println("Networks (" + nets.size() + "):");
        for (Network.Record net : nets)
            System.out.println("  - " + net.nameLabel + ": " + net.PIFs.size() + " PIF(s), " + net.VIFs.size() + " VIF(s)");
        System.out.println("OK: list-networks");
        Session.logout(conn);
    }
}
