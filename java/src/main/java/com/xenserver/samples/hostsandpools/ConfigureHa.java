package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureHa {
    private ConfigureHa() {
    }

    /**
     * Configure high availability.
     *
     * <p>Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many
     * host failures the pool can tolerate, enable HA, then disable it again.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureHa.run("https://xenserver", "root", password, "Shared NFS");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String heartbeatSrName) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAllRecords(conn).keySet().iterator().next();

        // The HA heartbeat statefile needs a shared SR; confirm the chosen one can host it.
        SR sr = srByName(conn, heartbeatSrName, true);
        System.out.println("Heartbeat SR:  " + sr.getNameLabel(conn));
        sr.assertCanHostHaStatefile(conn);

        // What HA does per VM. The restart priority decides which guests come back first after a host
        // failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
        VM guest = null;
        for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
            VM.Record r = e.getValue();
            if (!r.isATemplate && !r.isControlDomain && !r.isASnapshot) { guest = e.getKey(); break; }
        }

        // How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those
        // (as XenCenter's HA wizard does): a target computed with none protected can be too high, and
        // protecting a VM afterwards then fails HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN.
        Map<VM, String> plan = new java.util.HashMap<>();
        plan.put(guest, "restart");
        long ntol = Pool.haComputeHypotheticalMaxHostFailuresToTolerate(conn, plan);
        System.out.println("Max failures:  " + ntol);
        pool.setHaHostFailuresToTolerate(conn, ntol);
        Set<SR> heartbeatSrs = new LinkedHashSet<>();
        heartbeatSrs.add(sr);
        Pool.enableHa(conn, heartbeatSrs, new java.util.HashMap<>());
        try {
            System.out.println("HA enabled:    " + pool.getHaEnabled(conn));

            String was = guest.getHaRestartPriority(conn);
            guest.setHaRestartPriority(conn, "restart");
            System.out.println(guest.getNameLabel(conn) + " priority: '" + was + "' -> '"
                    + guest.getHaRestartPriority(conn) + "'");
            guest.setHaRestartPriority(conn, was);

            // And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
            // failure HA should undo, or an administrator's intent it should respect?
            boolean internal = pool.getHaRebootVmOnInternalShutdown(conn);
            System.out.println("Restart on internal shutdown: " + internal);
        } finally {
            // Turn HA back off however the above went: left on, it blocks host reboots, coordinator
            // changes and more (HA_IS_ENABLED, HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN).
            Pool.disableHa(conn);
        }
        System.out.println("HA enabled:    " + pool.getHaEnabled(conn));
        System.out.println("OK: configure-ha");
        Session.logout(conn);
    }
}
