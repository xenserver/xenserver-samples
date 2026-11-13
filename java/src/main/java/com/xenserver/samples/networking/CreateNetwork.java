package com.xenserver.samples.networking;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class CreateNetwork {
    private CreateNetwork() {
    }

    /**
     * Create a network.
     *
     * <p>Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to
     * each other privately.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateNetwork.run("https://xenserver", "root", password, "sdk-example-net");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String networkName) throws Exception {
        Connection conn = connect(url, user, password);
        Network.Record record = new Network.Record();
        record.nameLabel = networkName;
        record.nameDescription = "Internal network created by the SDK example";
        record.MTU = 1500L;
        record.otherConfig = new java.util.HashMap<>();
        // Managed by xapi (bridge and PIFs created for it). Say so: this binding sends every field,
        // and an unset boolean goes as false - an unmanaged network, which a bond refuses.
        record.managed = true;

        Network net = Network.create(conn, record);
        System.out.println("Created network: " + net.getUuid(conn));

        // Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this
        // is a property of the network rather than of any one interface on it.
        net.setMTU(conn, 9000L);
        System.out.println("MTU now:         " + net.getMTU(conn));

        net.destroy(conn);
        System.out.println("OK: create-network");
        Session.logout(conn);
    }
}
