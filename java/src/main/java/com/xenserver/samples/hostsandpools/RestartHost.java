package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.enableWhenBooted;
import static com.xenserver.samples.PoolConnection.connect;

public final class RestartHost {
    private RestartHost() {
    }

    /**
     * Restart a host.
     *
     * <p>Take a host down and bring it back: stop it accepting new VMs, move the ones it is running
     * elsewhere, reboot it, then power it right off and back on again.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Rebooting a host is never just the reboot: anything running on it has to go somewhere
            // first, and the host has to stop accepting new VMs while that happens.
            //
            // Not the coordinator: it is the host this session is talking to, and taking it down would
            // drop the connection underneath the rest of the example.
            Host coordinator = Pool.getAll(conn).iterator().next().getMaster(conn);
            Host host = null;
            for (Host h : Host.getAll(conn)) if (!h.equals(coordinator)) { host = h; break; }

            System.out.println("Restarting " + host.getNameLabel(conn));
            System.out.printf("  enabled=%s, guests=%d%n", host.getEnabled(conn), guestCount(conn, host));

            // Disabled means "accept no new VMs"; it does not move anything on its own.
            host.disable(conn);
            System.out.println("  disabled:   enabled=" + host.getEnabled(conn));

            // Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain - the
            // host's own management VM, which cannot move - is left.
            host.evacuate(conn);
            System.out.printf("  evacuated:  guests=%d%n", guestCount(conn, host));

            host.reboot(conn);
            // A real reboot takes minutes. Wait for the host to drop out and come back (live in its
            // host_metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
            // itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
            // never does - so enable it explicitly rather than depend on either.
            waitForHostLive(conn, host, false, 600_000, 2_000);
            waitForHostLive(conn, host, true, 1_200_000, 10_000);
            enableWhenBooted(conn, host);
            System.out.println("  rebooted, re-enabled: enabled=" + host.getEnabled(conn));

            // The other ending: off, and back on out of band - but only demonstrated if that is actually
            // configured, and waiting for each transition before starting the next. A real host.power_on
            // has no retry of its own and simply fails, "The host failed to power on.", if no mechanism is
            // configured or working.
            if (host.getPowerOnMode(conn) != null && !host.getPowerOnMode(conn).isEmpty()) {
                host.disable(conn);
                host.shutdown(conn);
                waitForHostLive(conn, host, false);
                System.out.println("  shut down:  live=" + host.getMetrics(conn).getLive(conn));
                host.powerOn(conn);
                waitForHostLive(conn, host, true, 1_200_000, 10_000);
                System.out.println("  powered on: live=" + host.getMetrics(conn).getLive(conn));
                enableWhenBooted(conn, host);
                System.out.println("  re-enabled: enabled=" + host.getEnabled(conn));
            } else {
                System.out.println("  skipping shutdown/power-on: no out-of-band power-on mode is "
                        + "configured on this host");
            }

            System.out.println("OK: restart-host");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Poll host_metrics.live until it matches, rather than issuing the next power command immediately -
     * real out-of-band power control has no retry of its own, so a tool that doesn't wait can issue a
     * second command while the first is still in flight.
     */
    private static void waitForHostLive(Connection conn, Host host, boolean want) throws Exception {
        waitForHostLive(conn, host, want, 60_000, 2000);
    }

    private static void waitForHostLive(Connection conn, Host host, boolean want, long timeoutMillis,
            long intervalMillis) throws Exception {
        long deadline = System.currentTimeMillis() + timeoutMillis;
        while (host.getMetrics(conn).getLive(conn) != want) {
            if (System.currentTimeMillis() > deadline)
                throw new RuntimeException("host did not reach live=" + want + " in time");
            Thread.sleep(intervalMillis);
        }
    }

    /**
     * Resident VMs excluding the control domain, which never moves.
     */
    private static int guestCount(Connection conn, Host host) throws Exception {
        int n = 0;
        for (VM vm : host.getResidentVMs(conn)) if (!vm.getIsControlDomain(conn)) n++;
        return n;
    }
}
