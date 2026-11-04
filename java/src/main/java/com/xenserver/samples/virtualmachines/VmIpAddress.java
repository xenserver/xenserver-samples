package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class VmIpAddress {
    private VmIpAddress() {
    }

    /**
     * Get a VM's IP address.
     *
     * <p>Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
     *
     * <p>A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
     * empty networks map) - retry for a while rather than giving up on the first look.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * VmIpAddress.run("https://xenserver", "root", password, 60_000, 2_000);
     * }</pre>
     */
    public static void run(String url, String user, String password,
            long timeoutMs, long intervalMs) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            long deadline = System.currentTimeMillis() + timeoutMs;
            while (true) {
                // A running guest reports its IP in networks, keyed "<vif device>/ip" (e.g. "0/ip").
                VM.Record vm = null;
                for (VM.Record r : VM.getAllRecords(conn).values())
                    if (r.powerState == Types.VmPowerState.RUNNING && !r.isATemplate && !r.isControlDomain
                            && !r.guestMetrics.toWireString().equals("OpaqueRef:NULL")) { vm = r; break; }
                String ip = null;
                if (vm != null) {
                    Map<String, String> networks = vm.guestMetrics.getRecord(conn).networks;
                    ip = networks.get("0/ip");
                }
                if (ip != null) {
                    System.out.println("  " + vm.nameLabel + ": " + ip);
                    break;
                }
                if (System.currentTimeMillis() > deadline)
                    throw new RuntimeException("no running guest reported an IP address within "
                            + (timeoutMs / 1000) + "s");
                Thread.sleep(intervalMs);
            }
            System.out.println("OK: vm-ip-address");
        } finally {
            Session.logout(conn);
        }
    }
}
