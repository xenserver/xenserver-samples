<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage TLS certificates

Install a pool-wide CA certificate, reset a host's server certificate, read the resulting fingerprints back, and turn on verification of the certificates members present to each other.

Workflow `manage-certificates`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/ManageCertificates.cs`](../../csharp/HostsAndPools/ManageCertificates.cs)

```csharp
/// <summary>
/// Install a pool-wide CA certificate, reset a host's server certificate, read the resulting fingerprints
/// back, and turn on verification of the certificates members present to each other.
/// </summary>
public static void ManageCertificates(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var hostRef = Host.get_all(session).First().opaque_ref;
    var poolRef = Pool.get_all(session).First().opaque_ref;
    var (certPem, keyPem) = SelfSignedCertPem();

    Console.WriteLine($"Certificates:   {Certificate.get_all(session).Count}");

    // ca=true: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
    // purpose=[]: general pool trust, not the licensing/ldaps-specific uses that enum also covers.
    // install_trusted_certificate returns nothing, so find the new record by diffing the set - the
    // current API; install_ca_certificate/uninstall_ca_certificate are its deprecated predecessors.
    var before = Certificate.get_all(session).ToHashSet();
    Pool.install_trusted_certificate(session, poolRef, true, certPem, new List<certificate_purpose>());
    var certRef = Certificate.get_all(session).Except(before).First().opaque_ref;
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
    var pool = Pool.get_all(session).First().opaque_ref;
    Console.WriteLine($"TLS verification: {Pool.get_tls_verification_enabled(session, pool)}");
    Pool.enable_tls_verification(session);
    Console.WriteLine($"  after enabling: {Pool.get_tls_verification_enabled(session, pool)}");
    Console.WriteLine("OK: manage-certificates");
    session.logout();
}

/// <summary> A throwaway self-signed certificate and private key (PEM). .NET's own X509 API builds
/// one directly - no external tool needed. </summary>
private static (string CertPem, string KeyPem) SelfSignedCertPem()
{
    using var rsa = RSA.Create(2048);
    var request = new System.Security.Cryptography.X509Certificates.CertificateRequest(
        "CN=sdk-example", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
    using var cert = request.CreateSelfSigned(
        DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(365));
    return (cert.ExportCertificatePem(), rsa.ExportRSAPrivateKeyPem());
}
```

<details><summary>Sample output</summary>

```text
Certificates:   5
After CA add:   6
Host certificate replaced with a real, generated certificate.
Host certificate reset (a fresh self-signed identity).
After CA remove:5
TLS verification: True
  after enabling: True
OK: manage-certificates
```

</details>

## Python

Source: [`python/hosts_and_pools/manage_certificates.py`](../../python/hosts_and_pools/manage_certificates.py)

```python
"""Manage TLS certificates.

Install a pool-wide CA certificate, reset a host's server certificate, read the resulting
fingerprints back, and turn on verification of the certificates members present to each other.
"""

import os
import subprocess
import tempfile

from connection import connect


def manage_certificates(url, username, password):
    """Install a pool-wide trusted certificate, replace a host's own TLS identity with a real
    certificate, reset it back to a fresh self-signed one, and read the counts back.

    A real, generated self-signed certificate, not a placeholder string: xapi decodes whatever is
    handed to install_trusted_certificate/install_server_certificate as PEM and rejects anything
    that isn't a well-formed certificate (INVALID_VALUE), so a dummy string fails.
    install_trusted_certificate/uninstall_trusted_certificate are the current API; the
    CA-specific pair this example used to call (install_ca_certificate/uninstall_ca_certificate)
    were deprecated in their favour."""
    session = connect(url, username, password)
    host_ref = session.xenapi.host.get_all()[0]
    pool_ref = session.xenapi.pool.get_all()[0]
    cert_pem, key_pem = _self_signed_cert_pem()

    print("Certificates:   %d" % len(session.xenapi.Certificate.get_all()))

    # ca=True: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
    # purpose=[]: general pool trust, not the licensing/ldaps-specific uses that enum also covers.
    # install_trusted_certificate returns nothing, so find the new record by diffing the set.
    before = set(session.xenapi.Certificate.get_all())
    session.xenapi.pool.install_trusted_certificate(pool_ref, True, cert_pem, [])
    cert_ref = next(iter(set(session.xenapi.Certificate.get_all()) - before))
    print("After CA add:   %d" % len(session.xenapi.Certificate.get_all()))

    # Actually replace the host's own TLS identity with a real certificate (what this workflow's
    # name promises, beyond CA trust), then reset it back to a fresh self-signed one.
    session.xenapi.host.install_server_certificate(host_ref, cert_pem, key_pem, "")
    print("Host certificate replaced with a real, generated certificate.")
    session.xenapi.host.reset_server_certificate(host_ref)
    print("Host certificate reset (a fresh self-signed identity).")

    session.xenapi.pool.uninstall_trusted_certificate(pool_ref, cert_ref)
    print("After CA remove:%d" % len(session.xenapi.Certificate.get_all()))

    # Separately from which certificates exist: whether the pool actually CHECKS the ones its members
    # present to each other. Turning it on is a one-way door from here -- there is no matching disable,
    # because a pool that could be talked out of verifying would not be verifying -- so the call is
    # idempotent and safe to repeat.
    pool = session.xenapi.pool.get_all()[0]
    print("TLS verification: %s" % session.xenapi.pool.get_tls_verification_enabled(pool))
    session.xenapi.pool.enable_tls_verification()
    print("  after enabling: %s" % session.xenapi.pool.get_tls_verification_enabled(pool))
    print("OK: manage-certificates")
    session.xenapi.session.logout()


def _self_signed_cert_pem():
    """A throwaway self-signed certificate and private key (PEM).

    Prefers the `cryptography` package (pure Python, no external tool needed) when it's installed;
    falls back to shelling out to `openssl req -x509` when it isn't, so this works either way
    without forcing an extra dependency on everyone."""
    try:
        import datetime
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.x509.oid import NameOID

        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "sdk-example")])
        now = datetime.datetime.utcnow()
        cert = (x509.CertificateBuilder()
                .subject_name(name).issuer_name(name).public_key(key.public_key())
                .serial_number(x509.random_serial_number())
                .not_valid_before(now - datetime.timedelta(days=1))
                .not_valid_after(now + datetime.timedelta(days=365))
                .sign(key, hashes.SHA256()))
        cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode()
        key_pem = key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption()).decode()
        return cert_pem, key_pem
    except ImportError:
        handle, keypath = tempfile.mkstemp(prefix="sdk-example-key-", suffix=".pem")
        os.close(handle)
        handle, certpath = tempfile.mkstemp(prefix="sdk-example-cert-", suffix=".pem")
        os.close(handle)
        try:
            subprocess.run(
                ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                 "-keyout", keypath, "-out", certpath, "-days", "365", "-subj", "/CN=sdk-example"],
                check=True, capture_output=True)
            with open(certpath) as f:
                cert_pem = f.read()
            with open(keypath) as f:
                key_pem = f.read()
            return cert_pem, key_pem
        finally:
            os.remove(keypath)
            os.remove(certpath)
```

<details><summary>Sample output</summary>

```text
Certificates:   5
After CA add:   6
Host certificate replaced with a real, generated certificate.
Host certificate reset (a fresh self-signed identity).
After CA remove:5
TLS verification: True
  after enabling: True
OK: manage-certificates
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ManageCertificates.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ManageCertificates.java)

```java
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
```

<details><summary>Sample output</summary>

```text
Certificates:   5
After CA add:   6
Host certificate replaced with a real, generated certificate.
Host certificate reset (a fresh self-signed identity).
After CA remove:5
TLS verification: true
  after enabling: true
OK: manage-certificates
```

</details>

## Go

Source: [`go/manage_certificates.go`](../../go/manage_certificates.go)

```go
package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"time"

	"go/xenapi"
)

// manageCertificates - Manage TLS certificates.
//
// Install a pool-wide CA certificate, reset a host's server certificate, read the resulting
// fingerprints back, and turn on verification of the certificates members present to each other.
func manageCertificates(url, user, password string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	poolRef := pools[0]

	// A real, generated self-signed certificate, not a placeholder string: xapi decodes whatever is
	// handed to install_trusted_certificate/install_server_certificate as PEM and rejects anything
	// that isn't a well-formed certificate (INVALID_VALUE).
	certPEM, keyPEM := selfSignedCertPEM()

	certs, _ := xenapi.Certificate.GetAll(session)
	fmt.Printf("Certificates:   %d\n", len(certs))

	// ca=true: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
	// purpose=[]: general pool trust. install_trusted_certificate is the current API (the
	// deprecated install_ca_certificate/uninstall_ca_certificate pair took a name instead) and
	// returns nothing, so find the new record by diffing the set.
	before := map[xenapi.CertificateRef]bool{}
	for _, ref := range certs {
		before[ref] = true
	}
	check(xenapi.Pool.InstallTrustedCertificate(session, poolRef, true, certPEM, []xenapi.CertificatePurpose{}))
	certs, _ = xenapi.Certificate.GetAll(session)
	fmt.Printf("After CA add:   %d\n", len(certs))
	var certRef xenapi.CertificateRef
	for _, ref := range certs {
		if !before[ref] {
			certRef = ref
			break
		}
	}

	// Actually replace the host's own TLS identity with a real certificate (beyond CA trust), then
	// reset it back to a fresh self-signed one, as before.
	check(xenapi.Host.InstallServerCertificate(session, hosts[0], certPEM, keyPEM, ""))
	fmt.Println("Host certificate replaced with a real, generated certificate.")
	check(xenapi.Host.ResetServerCertificate(session, hosts[0]))
	fmt.Println("Host certificate reset (a fresh self-signed identity).")

	check(xenapi.Pool.UninstallTrustedCertificate(session, poolRef, certRef))
	certs, _ = xenapi.Certificate.GetAll(session)
	fmt.Printf("After CA remove:%d\n", len(certs))

	// Separately from which certificates exist: whether the pool actually CHECKS the ones its members
	// present to each other. Turning it on is a one-way door from here - there is no matching disable,
	// because a pool that could be talked out of verifying would not be verifying - so the call is
	// idempotent and safe to repeat.
	verifying, _ := xenapi.Pool.GetTLSVerificationEnabled(session, poolRef)
	fmt.Printf("TLS verification: %t\n", verifying)
	check(xenapi.Pool.EnableTLSVerification(session))
	verifying, _ = xenapi.Pool.GetTLSVerificationEnabled(session, poolRef)
	fmt.Printf("  after enabling: %t\n", verifying)
	fmt.Println("OK: manage-certificates")
	session.Logout()
}

// selfSignedCertPEM generates a throwaway self-signed certificate and private key (PEM). Go's
// standard library crypto/x509 and crypto/rsa need no external tool for this, unlike some other
// languages here.
func selfSignedCertPEM() (certPEM, keyPEM string) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	check(err)
	template := x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()),
		Subject:      pkix.Name{CommonName: "sdk-example"},
		NotBefore:    time.Now().Add(-24 * time.Hour),
		NotAfter:     time.Now().Add(365 * 24 * time.Hour),
	}
	der, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	check(err)
	certPEM = string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))
	keyPEM = string(pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)}))
	return
}
```

<details><summary>Sample output</summary>

```text
Certificates:   5
After CA add:   6
Host certificate replaced with a real, generated certificate.
Host certificate reset (a fresh self-signed identity).
After CA remove:5
TLS verification: true
  after enabling: true
OK: manage-certificates
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ManageCertificates.ps1`](../../powershell/HostsAndPools/Invoke-ManageCertificates.ps1)

```powershell
function Invoke-ManageCertificates {
    <#
    .SYNOPSIS
        Manage TLS certificates.
    .DESCRIPTION
        Install a pool-wide CA certificate, reset a host's server certificate, read the resulting
        fingerprints back, and turn on verification of the certificates members present to each other.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $pool = Get-XenPool | Select-Object -First 1
    # A real, generated self-signed certificate, not a placeholder string: xapi decodes whatever is
    # handed to InstallTrustedCertificate/InstallServerCertificate as PEM and rejects anything that
    # isn't a well-formed certificate (INVALID_VALUE) on a real host.
    $certPem, $keyPem = Get-SelfSignedCertPem
    Write-Host "Certificates:   $(@(Get-XenCertificate).Count)"

    # Ca=$true: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
    # Purpose=@(): general pool trust, not the licensing/ldaps-specific uses that enum also covers.
    # InstallTrustedCertificate returns nothing, so find the new record by diffing the set.
    # InstallTrustedCertificate/UninstallTrustedCertificate are the current API; the CA-specific pair
    # this example used to call (InstallCaCertificate/UninstallCaCertificate) were deprecated in favour.
    $before = @(Get-XenCertificate | ForEach-Object { $_.opaque_ref })
    Invoke-XenPool -Ref $pool.opaque_ref -XenAction InstallTrustedCertificate -Cert $certPem -Ca $true -Purpose @()
    $certRef = @(Get-XenCertificate | ForEach-Object { $_.opaque_ref } | Where-Object { $before -notcontains $_ })[0]
    Write-Host "After CA add:   $(@(Get-XenCertificate).Count)"

    # Actually replace the host's own TLS identity with a real certificate (what this workflow's name
    # promises, beyond CA trust), then reset it back to a fresh self-signed one.
    Invoke-XenHost -Ref $xenHost.opaque_ref -XenAction InstallServerCertificate `
        -Certificate $certPem -PrivateKey $keyPem -CertificateChain ''
    Write-Host "Host certificate replaced with a real, generated certificate."

    Invoke-XenHost -Ref $xenHost.opaque_ref -XenAction ResetServerCertificate
    Write-Host "Host certificate reset (a fresh self-signed identity)."

    Invoke-XenPool -Ref $pool.opaque_ref -XenAction UninstallTrustedCertificate -Certificate $certRef
    Write-Host "After CA remove:$(@(Get-XenCertificate).Count)"

    # Separately from which certificates exist: whether the pool actually CHECKS the ones its members
    # present to each other. Turning it on is a one-way door from here - there is no matching disable,
    # because a pool that could be talked out of verifying would not be verifying - so the call is
    # idempotent and safe to repeat.
    Write-Host "TLS verification: $(Get-XenPoolProperty -Ref $pool.opaque_ref -XenProperty TlsVerificationEnabled)"
    Invoke-XenPool -Ref $pool.opaque_ref -XenAction EnableTlsVerification
    Write-Host "  after enabling: $(Get-XenPoolProperty -Ref $pool.opaque_ref -XenProperty TlsVerificationEnabled)"
    Write-Host "OK: manage-certificates"
    Disconnect-XenServer -Session $session
}

function Get-SelfSignedCertPem {
    <#
    .SYNOPSIS
        A throwaway self-signed certificate and private key (PEM).
    .DESCRIPTION
        PowerShell 7 runs on .NET, which has a native crypto API for this - no external tool needed (unlike
        PowerShell 5.1, where New-SelfSignedCertificate, or an `openssl req -x509` shell-out would be the
        fallback).
    #>
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        "CN=sdk-example", $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $cert = $req.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1), [DateTimeOffset]::UtcNow.AddDays(365))
    return $cert.ExportCertificatePem(), $rsa.ExportPkcs8PrivateKeyPem()
}
```

<details><summary>Sample output</summary>

```text
Certificates:   5
After CA add:   6
Host certificate replaced with a real, generated certificate.
Host certificate reset (a fresh self-signed identity).
After CA remove:5
TLS verification: True
  after enabling: True
OK: manage-certificates
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/manage-certificates.sh`](../../cli/hosts-and-pools/manage-certificates.sh)

```bash
# Manage TLS certificates.
#
# Install a pool-wide CA certificate, reset a host's server certificate, read the resulting fingerprints back,
# and turn on verification of the certificates members present to each other.
#
# Run it:
#   ./workflows.sh manage-certificates https://xenserver root "$password"

manage_certificates() {
    h=$(first_host)
    echo "Certificates:   $(count_csv "$(xe certificate-list --minimal)")"

    # A real, generated self-signed certificate, not a placeholder string: xapi decodes whatever is handed
    # to pool-install-trusted-certificate/host-server-certificate-install as PEM and rejects anything that
    # isn't a well-formed certificate (INVALID_VALUE). filename=/certificate=/private-key= are local files
    # xe uploads itself, the same convention vm-export/vm-import already use in this script.
    local certfile=cli-example-cert.pem keyfile=cli-example-key.pem before after cert_uuid
    rm -f "$certfile" "$keyfile"
    self_signed_cert "$certfile" "$keyfile"

    # pool-install-trusted-certificate/pool-uninstall-trusted-certificate are the current API; the
    # deprecated pool-*-ca-certificate pair (by name, not by uuid) is superseded by this one.
    # ca=true: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
    before=$(xe certificate-list --minimal)
    xe pool-install-trusted-certificate filename="$certfile" ca=true
    after=$(xe certificate-list --minimal)
    echo "After CA add:   $(count_csv "$after")"
    cert_uuid=""
    for c in $(each_csv "$after"); do
        case ",$before," in *",$c,"*) ;; *) cert_uuid=$c ;; esac
    done

    # Actually replace the host's own TLS identity with a real certificate (what this workflow's name
    # promises, beyond CA trust), then reset it back to a fresh self-signed one.
    xe host-server-certificate-install uuid=$h certificate="$certfile" private-key="$keyfile"
    echo "Host certificate replaced with a real, generated certificate."
    xe host-reset-server-certificate uuid=$h
    echo "Host certificate reset (a fresh self-signed identity)."

    xe pool-uninstall-trusted-certificate certificate-uuid=$cert_uuid
    rm -f "$certfile" "$keyfile"
    echo "After CA remove:$(count_csv "$(xe certificate-list --minimal)")"

    # Separately from which certificates exist: whether the pool actually CHECKS the ones its members
    # present to each other. There is no matching disable - a pool that could be talked out of verifying
    # would not be verifying - and the enable is idempotent, so this is safe to repeat.
    p=$(first_csv "$(xe pool-list --minimal)")
    echo "TLS verification: $(xe pool-param-get uuid=$p param-name=tls-verification-enabled)"
    xe pool-enable-tls-verification
    echo "  after enabling: $(xe pool-param-get uuid=$p param-name=tls-verification-enabled)"
    echo "OK: manage-certificates"
}

# A throwaway self-signed certificate and private key (PEM). bash has no native crypto library, so
# shell out to openssl for this.
self_signed_cert() {
    local certfile=$1 keyfile=$2
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$keyfile" -out "$certfile" \
        -days 365 -subj /CN=sdk-example 2>/dev/null
}
```

<details><summary>Sample output</summary>

```text
Certificates:   5
00000001-0000-0000-fb0a-000000000000
After CA add:   6
Host certificate replaced with a real, generated certificate.
Host certificate reset (a fresh self-signed identity).
After CA remove:5
TLS verification: true
  after enabling: true
OK: manage-certificates
```

</details>
