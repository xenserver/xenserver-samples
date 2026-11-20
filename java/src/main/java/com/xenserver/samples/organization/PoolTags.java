package com.xenserver.samples.organization;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class PoolTags {
    private PoolTags() {
    }

    /**
     * Tag the pool.
     *
     * <p>Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and
     * hosts.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * PoolTags.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        pool.addTags(conn, "sdk-managed");
        System.out.println("Pool tags: " + String.join(", ", pool.getTags(conn)));
        pool.removeTags(conn, "sdk-managed");
        System.out.println("OK: pool-tags");
        Session.logout(conn);
    }
}
