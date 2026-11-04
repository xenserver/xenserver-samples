package com.xenserver.samples.networking;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVif {
    private ManageVif() {
    }

    /**
     * Manage network interfaces.
     *
     * <p>Attach a virtual network interface to a VM and remove it again.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageVif.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vif");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm);
        Network net = Network.getAll(conn).iterator().next();
        String device = vm.getAllowedVIFDevices(conn).iterator().next();

        VIF.Record vifRec = new VIF.Record();
        vifRec.VM = vm;
        vifRec.network = net;
        vifRec.device = device;
        vifRec.MAC = "";
        vifRec.MTU = 1500L;
        vifRec.otherConfig = new java.util.HashMap<>();
        vifRec.qosAlgorithmType = "";
        vifRec.qosAlgorithmParams = new java.util.HashMap<>();
        // Left unset, the binding's Record defaults these two enums to its own UNRECOGNIZED sentinel,
        // which released xapi rejects outright rather than treating as "no IP configured". Say so
        // explicitly.
        vifRec.ipv4ConfigurationMode = Types.VifIpv4ConfigurationMode.NONE;
        vifRec.ipv6ConfigurationMode = Types.VifIpv6ConfigurationMode.NONE;
        VIF vif = VIF.create(conn, vifRec);
        System.out.println("Attached a VIF on device " + device + "; VM now has "
                + vm.getVIFs(conn).size() + " NIC(s)");

        vif.destroy(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: manage-vif");
        Session.logout(conn);
    }
}
