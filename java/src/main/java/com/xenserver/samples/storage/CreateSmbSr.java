package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Secret;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.Helpers.detachAndForgetSr;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateSmbSr {
    private CreateSmbSr() {
    }

    /**
     * Create an SMB SR.
     *
     * <p>Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
     * credentials (the password as a secret, never in plain text).
     *
     * <p>Connect a shared SR to an SMB/CIFS file share (create validates + sizes from the share). The
     * password travels as a Secret, not plaintext device-config.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateSmbSr.run("https://xenserver", "root", password, "192.0.2.40", "/vmstore", "Administrator",
     * "Password1", "sdk-example-smb");
     * }</pre>
     */
    public static void run(String url, String user, String password, String server, String share,
            String smbUsername, String smbPassword, String srName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        try {
            Host host = Host.getAllRecords(conn).keySet().iterator().next();
            Secret.Record secretRec = new Secret.Record();
            secretRec.value = smbPassword;
            secretRec.otherConfig = new java.util.HashMap<>();
            Secret secret = Secret.create(conn, secretRec);

            Map<String, String> dc = new java.util.HashMap<>();
            // server is the share as one UNC path, //server/share: the SMB driver has no separate serverpath.
            dc.put("server", "//" + server + share);
            dc.put("username", smbUsername);
            dc.put("password_secret", secret.getUuid(conn));
            SR sr = SR.create(conn, host, dc, 0L, srName, "SMB SR created by the SDK example",
                "smb", "user", true, new java.util.HashMap<>());
            System.out.println("Created SR: " + sr.getUuid(conn) + " (" + sr.getPhysicalSize(conn) / GiB + " GiB)");
            detachAndForgetSr(conn, sr);
            secret.destroy(conn);
            System.out.println("OK: create-smb-sr");
        } finally {
            Session.logout(conn);
        }
    }
}
