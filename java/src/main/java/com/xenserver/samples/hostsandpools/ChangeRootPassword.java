package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class ChangeRootPassword {
    private ChangeRootPassword() {
    }

    /**
     * Change the root password.
     *
     * <p>Change the local superuser password, handle the wrong-old-password failure, and change it back.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        final String temporary = "sdk-example-temp-password";

        // changePassword takes the OLD password as well as the new one, even though you are already
        // authenticated.
        Session.changePassword(conn, password, temporary);
        System.out.println("Password changed.");

        // The existing session stays valid afterwards - only NEW connections need the new password.
        System.out.println("Session still usable: " + (Pool.getAll(conn).size() == 1));

        // Not demonstrated: a "wrong old password is rejected" check. session.change_password on a
        // ROOT session ignores old_pwd entirely (CA-13567, confirmed in xapi_session.ml) - the call
        // succeeds regardless of what's passed as the old password. The real gate is that only a
        // session with is_local_superuser may call this at all.

        Session.changePassword(conn, temporary, password);
        System.out.println("Password restored.");
        System.out.println("OK: change-root-password");
        Session.logout(conn);
    }
}
