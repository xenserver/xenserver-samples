package com.xenserver.samples.gettingstarted;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConnectInventory {
    private ConnectInventory() {
    }

    /**
     * Connect &amp; inventory.
     *
     * <p>Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the
     * virtual machines with their power state. This is the starting point for every session.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConnectInventory.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Pool.Record pool = Pool.getAllRecords(conn).values().iterator().next();
        System.out.println("Connected to pool: " + pool.nameLabel);

        Map<Host, Host.Record> hosts = Host.getAllRecords(conn);
        System.out.println("Hosts (" + hosts.size() + "):");
        for (Host.Record h : hosts.values())
            System.out.println("  - " + h.nameLabel + " (" + h.address + ")");

        int count = 0;
        System.out.println("VMs:");
        for (VM.Record v : VM.getAllRecords(conn).values()) {
            if (!v.isATemplate && !v.isControlDomain) {
                count++;
                System.out.println("  - " + v.nameLabel + " [" + v.powerState + "]");
            }
        }
        System.out.println("VMs (" + count + ")");

        System.out.println("OK: connect-inventory");
        Session.logout(conn);
    }
}
