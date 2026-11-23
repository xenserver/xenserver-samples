package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureHostStorage {
    private ConfigureHostStorage() {
    }

    /**
     * Configure host storage.
     *
     * <p>Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureHostStorage.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // The IQN identifies this host to iSCSI targets, so a target's access list is written
            // against it - changing it on a host with live iSCSI storage cuts it off. Existing iSCSI
            // SRs must be detached first: changing the IQN underneath them can make the host unable to
            // reconnect to new or existing SRs until the storage target is updated to match. Multipathing
            // uses every path to the storage rather than one, and on real hardware you put the host into
            // maintenance mode before changing it, because the paths are rebuilt.
            Host host = Pool.getAll(conn).iterator().next().getMaster(conn);

            String beforeIqn = host.getIscsiIqn(conn);
            boolean beforeMultipathing = host.getMultipathing(conn);
            System.out.println(host.getNameLabel(conn) + ": iSCSI IQN '" + beforeIqn
                    + "', multipathing " + beforeMultipathing);

            host.setIscsiIqn(conn, "iqn.2026-01.com.example:" + host.getNameLabel(conn));
            host.setMultipathing(conn, true);
            System.out.println("  IQN now:      " + host.getIscsiIqn(conn));
            System.out.println("  multipathing: " + host.getMultipathing(conn));

            // set_iscsi_iqn refuses an empty string (INVALID_VALUE); only restore it if this host actually
            // had one set before - a host that has never had an IQN configured has it empty, and there is
            // no way to set it back to empty through this call.
            if (beforeIqn != null && !beforeIqn.isEmpty()) host.setIscsiIqn(conn, beforeIqn);
            host.setMultipathing(conn, beforeMultipathing);
            System.out.println("  restored");
            System.out.println("OK: configure-host-storage");
        } finally {
            Session.logout(conn);
        }
    }
}
