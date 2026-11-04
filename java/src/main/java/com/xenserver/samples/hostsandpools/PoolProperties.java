package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class PoolProperties {
    private PoolProperties() {
    }

    /**
     * Pool properties.
     *
     * <p>Read the pool name and default storage repository, then rename the pool and restore it.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * PoolProperties.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        String original = pool.getNameLabel(conn);
        SR defaultSr = pool.getDefaultSR(conn);
        System.out.println("Pool:       '" + original + "'");
        System.out.println("Default SR: " + (defaultSr.toWireString().equals("OpaqueRef:NULL")
                ? "(none)" : defaultSr.getNameLabel(conn)));

        pool.setNameLabel(conn, "sdk-pool-renamed");
        System.out.println("Renamed to: '" + pool.getNameLabel(conn) + "'");
        pool.setNameLabel(conn, original); // restore
        System.out.println("OK: pool-properties");
        Session.logout(conn);
    }
}
