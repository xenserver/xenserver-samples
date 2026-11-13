package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class VmIpAddress {
    private VmIpAddress() {
    }

    /**
     * Get a VM's IP address.
     *
     * <p>Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.
     *
     * <p>A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
     * empty networks map) - retry for a while before concluding it has no guest agent reporting.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * VmIpAddress.run("https://xenserver", "root", password, "web-01", 60_000, 2_000);
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName,
            long timeoutMs, long intervalMs) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = vmByName(conn, vmName);
            long deadline = System.currentTimeMillis() + timeoutMs;
            String ip = null;
            while (true) {
                // An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
                VM.Record record = vm.getRecord(conn);
                ip = null;
                if (record.powerState == Types.VmPowerState.RUNNING && !record.guestMetrics.isNull()) {
                    Map<String, String> networks = record.guestMetrics.getRecord(conn).networks;
                    ip = networks.get("0/ip");
                }
                if ((ip != null && !ip.isEmpty()) || System.currentTimeMillis() > deadline) break;
                Thread.sleep(intervalMs);
            }
            if (ip != null && !ip.isEmpty()) {
                System.out.println("  " + vmName + ": " + ip);
            } else {
                System.out.println("  " + vmName + ": no IP address reported yet (no guest agent running?)");
            }
            System.out.println("OK: vm-ip-address");
        } finally {
            Session.logout(conn);
        }
    }
}
