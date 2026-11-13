using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Install a pool-wide CA certificate, reset a host's server certificate, read the resulting fingerprints
    /// back, and turn on verification of the certificates members present to each other.
    /// </summary>
    public static void ManageCertificates(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var hostRef = Host.get_all(session).First();
        var poolRef = Pool.get_all(session).First();
        var (certPem, keyPem) = SelfSignedCertPem();

        Console.WriteLine($"Certificates:   {Certificate.get_all(session).Count}");

        // ca=true: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
        // purpose=[]: general pool trust, not the licensing/ldaps-specific uses that enum also covers.
        // install_trusted_certificate returns nothing, so find the new record by diffing the set - the
        // current API; install_ca_certificate/uninstall_ca_certificate are its deprecated predecessors.
        var before = Certificate.get_all(session).ToHashSet();
        Pool.install_trusted_certificate(session, poolRef, true, certPem, new List<certificate_purpose>());
        var certRef = Certificate.get_all(session).Except(before).First();
        Console.WriteLine($"After CA add:   {Certificate.get_all(session).Count}");

        // Actually replace the host's own TLS identity with a real certificate (what this workflow's
        // name promises, beyond CA trust), then reset it back to a fresh self-signed one.
        Host.install_server_certificate(session, hostRef, certPem, keyPem, "");
        Console.WriteLine("Host certificate replaced with a real, generated certificate.");
        Host.reset_server_certificate(session, hostRef);
        Console.WriteLine("Host certificate reset (a fresh self-signed identity).");

        Pool.uninstall_trusted_certificate(session, poolRef, certRef);
        Console.WriteLine($"After CA remove:{Certificate.get_all(session).Count}");

        // Separately from which certificates exist: whether the pool actually CHECKS the ones its members
        // present to each other. Turning it on is a one-way door from here — there is no matching disable,
        // because a pool that could be talked out of verifying would not be verifying — so the call is
        // idempotent and safe to repeat.
        var pool = Pool.get_all(session).First();
        Console.WriteLine($"TLS verification: {Pool.get_tls_verification_enabled(session, pool)}");
        Pool.enable_tls_verification(session);
        Console.WriteLine($"  after enabling: {Pool.get_tls_verification_enabled(session, pool)}");
        Console.WriteLine("OK: manage-certificates");
        session.logout();
    }

    /// <summary>
    /// A throwaway self-signed certificate and private key (PEM). .NET's own X509 API builds one directly -
    /// no external tool needed.
    /// </summary>
    private static (string CertPem, string KeyPem) SelfSignedCertPem()
    {
        using var rsa = RSA.Create(2048);
        var request = new System.Security.Cryptography.X509Certificates.CertificateRequest(
            "CN=sdk-example", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        using var cert = request.CreateSelfSigned(
            DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(365));
        return (cert.ExportCertificatePem(), rsa.ExportRSAPrivateKeyPem());
    }
}
