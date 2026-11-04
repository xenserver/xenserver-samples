package com.xenserver.samples.networking;

import com.xensource.xenapi.Bond;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.PIF;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

public final class CreateBond {
    private CreateBond() {
    }

    /**
     * Create a NIC bond.
     *
     * <p>Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond
     * back, then dissolve it.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateBond.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Host xenHost = Host.getAll(conn).iterator().next();

            // Pick up any NIC racked since the host booted. Cheap, and without it a card added a moment
            // ago is not there to bond.
            PIF.scan(conn, xenHost);

            // Spare NICs only. A bond that includes the management interface moves the management
            // address onto the bond master — on a real host that is how you lose your connection.
            Set<PIF> spares = new LinkedHashSet<PIF>();
            for (Map.Entry<PIF, PIF.Record> e : PIF.getAllRecords(conn).entrySet()) {
                if (e.getValue().host.equals(xenHost) && !e.getValue().management && e.getValue().physical
                        && spares.size() < 2) {
                    spares.add(e.getKey());
                }
            }
            if (spares.size() < 2)
                throw new RuntimeException(xenHost.getNameLabel(conn) + " has " + spares.size()
                        + " spare NIC(s); a bond needs two that aren't the management interface");
            StringBuilder devices = new StringBuilder();
            for (PIF p : spares) devices.append(devices.length() > 0 ? ", " : "").append(p.getDevice(conn));
            System.out.println("Bonding:      " + devices);

            // The bond needs a network to sit on.
            Network.Record netSpec = new Network.Record();
            netSpec.nameLabel = "sdk-example-bond";
            netSpec.nameDescription = "Created by the SDK example";
            netSpec.otherConfig = new HashMap<String, String>();
            netSpec.managed = true;   // as in createNetwork: unset would send false (NETWORK_UNMANAGED)
            Network network = Network.create(conn, netSpec);

            Bond bond = Bond.create(conn, network, spares, "", Types.BondMode.BALANCE_SLB);
            System.out.println("Bond master:  " + bond.getMaster(conn).getDevice(conn));
            System.out.println("Mode:         " + bond.getMode(conn));

            bond.destroy(conn);
            network.destroy(conn);
            System.out.println("Bonds left:   " + Bond.getAll(conn).size());
            System.out.println("OK: create-bond");
        } finally {
            Session.logout(conn);
        }
    }
}
