package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigurePoolOptions {
    private ConfigurePoolOptions() {
    }

    /**
     * Configure pool options.
     *
     * <p>Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping
     * and memory-migration compression — then put them back.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigurePoolOptions.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // These are plain pool settings, each a single field. Read them, change them, put them back.
            Pool pool = Pool.getAll(conn).iterator().next();

            boolean beforeLivePatching = pool.getLivePatchingDisabled(conn);
            boolean beforeIgmp = pool.getIgmpSnoopingEnabled(conn);
            boolean beforeMigrationCompression = pool.getMigrationCompression(conn);
            System.out.printf("  %-22s %s%n", "live patching disabled", beforeLivePatching);
            System.out.printf("  %-22s %s%n", "IGMP snooping", beforeIgmp);
            System.out.printf("  %-22s %s%n", "migration compression", beforeMigrationCompression);

            // Live patching applies host updates without a reboot; disabling it forces the reboot.
            pool.setLivePatchingDisabled(conn, !beforeLivePatching);
            // IGMP snooping keeps multicast off ports that did not ask for it.
            pool.setIgmpSnoopingEnabled(conn, !beforeIgmp);
            // Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
            pool.setMigrationCompression(conn, !beforeMigrationCompression);

            System.out.println("after changing:");
            System.out.printf("  %-22s %s%n", "live patching disabled", pool.getLivePatchingDisabled(conn));
            System.out.printf("  %-22s %s%n", "IGMP snooping", pool.getIgmpSnoopingEnabled(conn));
            System.out.printf("  %-22s %s%n", "migration compression", pool.getMigrationCompression(conn));

            pool.setLivePatchingDisabled(conn, beforeLivePatching);
            pool.setIgmpSnoopingEnabled(conn, beforeIgmp);
            pool.setMigrationCompression(conn, beforeMigrationCompression);
            System.out.println("  restored");
            System.out.println("OK: configure-pool-options");
        } finally {
            Session.logout(conn);
        }
    }
}
