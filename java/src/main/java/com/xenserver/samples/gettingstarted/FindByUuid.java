package com.xenserver.samples.gettingstarted;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class FindByUuid {
    private FindByUuid() {
    }

    /**
     * Look up an object by UUID.
     *
     * <p>Resolve a stable UUID back to a live object reference — how to persist a reference to an object
     * across sessions.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * FindByUuid.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        // UUIDs are stable identifiers you can persist and resolve back to a (session-scoped) ref.
        VM vm = vmByName(conn, vmName);
        String uuid = vm.getUuid(conn);
        VM resolved = VM.getByUuid(conn, uuid);
        System.out.println("UUID " + uuid + " resolves to " + resolved.getNameLabel(conn));
        System.out.println("Same object: " + resolved.equals(vm));
        System.out.println("OK: find-by-uuid");
        Session.logout(conn);
    }
}
