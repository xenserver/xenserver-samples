package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Certificate;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageCertificates {
    private ManageCertificates() {
    }

    /**
     * Manage TLS certificates.
     *
     * <p>Install a pool-wide CA certificate, reset a host's server certificate, read the resulting
     * fingerprints back, and turn on verification of the certificates members present to each other.
     *
     * <p>Install a pool-wide trusted certificate, replace a host's own TLS identity with a real
     * certificate, reset it back to a fresh self-signed one, and read the counts back.
     *
     * <p>A real, generated self-signed certificate, not a placeholder string: xapi decodes whatever is
     * handed to installTrustedCertificate/installServerCertificate as PEM and rejects anything that isn't
     * a well-formed certificate (INVALID_VALUE), so a dummy string fails.
     * installTrustedCertificate/uninstallTrustedCertificate are the current API; the CA-specific pair this
     * example used to call (installCaCertificate/uninstallCaCertificate) were deprecated in their favour.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Host host = Host.getAll(conn).iterator().next();
        Pool pool = Pool.getAll(conn).iterator().next();
        String[] certAndKey = selfSignedCertPem();
        String certPem = certAndKey[0], keyPem = certAndKey[1];

        System.out.println("Certificates:   " + Certificate.getAll(conn).size());

        // ca=true: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
        // purpose=[]: general pool trust, not the licensing/ldaps-specific uses that enum also covers.
        // installTrustedCertificate returns nothing, so find the new record by diffing the set.
        Set<Certificate> before = Certificate.getAll(conn);
        pool.installTrustedCertificate(conn, true, certPem, new java.util.HashSet<Types.CertificatePurpose>());
        Set<Certificate> after = Certificate.getAll(conn);
        after.removeAll(before);
        Certificate certRef = after.iterator().next();
        System.out.println("After CA add:   " + Certificate.getAll(conn).size());

        // Actually replace the host's own TLS identity with a real certificate (what this workflow's name
        // promises, beyond CA trust), then reset it back to a fresh self-signed one.
        host.installServerCertificate(conn, certPem, keyPem, "");
        System.out.println("Host certificate replaced with a real, generated certificate.");
        host.resetServerCertificate(conn);
        System.out.println("Host certificate reset (a fresh self-signed identity).");

        pool.uninstallTrustedCertificate(conn, certRef);
        System.out.println("After CA remove:" + Certificate.getAll(conn).size());

        // Separately from which certificates exist: whether the pool actually CHECKS the ones its
        // members present to each other. Turning it on is a one-way door from here - there is no
        // matching disable, because a pool that could be talked out of verifying would not be
        // verifying - so the call is idempotent and safe to repeat.
        System.out.println("TLS verification: " + pool.getTlsVerificationEnabled(conn));
        Pool.enableTlsVerification(conn);
        System.out.println("  after enabling: " + pool.getTlsVerificationEnabled(conn));
        System.out.println("OK: manage-certificates");
        Session.logout(conn);
    }

    /**
     * A throwaway self-signed certificate and private key (PEM). Java has no dependency-free public API to
     * mint an X.509 certificate (the internal sun.security.x509 classes need extra JVM flags under the
     * module system), so shell out to openssl and read the two PEM files back.
     */
    private static String[] selfSignedCertPem() throws Exception {
        java.io.File keyFile = java.io.File.createTempFile("sdk-example-key-", ".pem");
        java.io.File certFile = java.io.File.createTempFile("sdk-example-cert-", ".pem");
        try {
            Process p = new ProcessBuilder("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-keyout", keyFile.getAbsolutePath(), "-out", certFile.getAbsolutePath(),
                    "-days", "365", "-subj", "/CN=sdk-example")
                    .redirectErrorStream(true).start();
            String output = new String(p.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
            int code = p.waitFor();
            if (code != 0) throw new RuntimeException("openssl failed (" + code + "): " + output);
            String certPem = java.nio.file.Files.readString(certFile.toPath());
            String keyPem = java.nio.file.Files.readString(keyFile.toPath());
            return new String[]{certPem, keyPem};
        } finally {
            keyFile.delete();
            certFile.delete();
        }
    }
}
