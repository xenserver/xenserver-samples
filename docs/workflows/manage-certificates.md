<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage TLS certificates

Install a pool-wide CA certificate, reset a host's server certificate, read the resulting fingerprints back, and turn on verification of the certificates members present to each other.

Workflow `manage-certificates`. [All workflows](README.md) · [Connecting](connecting.md)

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
    $before = @(Get-XenCertificate | ForEach-Object { $_.uuid })
    Invoke-XenPool -Ref $pool -XenAction InstallTrustedCertificate -Cert $certPem -Ca $true -Purpose @()
    $cert = @(Get-XenCertificate | Where-Object { $before -notcontains $_.uuid })[0]
    Write-Host "After CA add:   $(@(Get-XenCertificate).Count)"

    try {
        # Actually replace the host's own TLS identity with a real certificate (what this workflow's
        # name promises, beyond CA trust), then reset it back to a fresh self-signed one.
        Invoke-XenHost -Ref $xenHost -XenAction InstallServerCertificate `
            -Certificate $certPem -PrivateKey $keyPem -CertificateChain ''
        Write-Host "Host certificate replaced with a real, generated certificate."
        Invoke-XenHost -Ref $xenHost -XenAction ResetServerCertificate
        Write-Host "Host certificate reset (a fresh self-signed identity)."
    }
    finally {
        # Uninstall the trusted CA certificate however the above went, or it outlives this example.
        Invoke-XenPool -Ref $pool -XenAction UninstallTrustedCertificate -Certificate $cert
    }
    Write-Host "After CA remove:$(@(Get-XenCertificate).Count)"

    # Separately from which certificates exist: whether the pool actually CHECKS the ones its members
    # present to each other. Turning it on is a one-way door from here - there is no matching disable,
    # because a pool that could be talked out of verifying would not be verifying - so the call is
    # idempotent and safe to repeat.
    Write-Host "TLS verification: $(Get-XenPoolProperty -Ref $pool -XenProperty TlsVerificationEnabled)"
    Invoke-XenPool -Ref $pool -XenAction EnableTlsVerification
    Write-Host "  after enabling: $(Get-XenPoolProperty -Ref $pool -XenProperty TlsVerificationEnabled)"
    Write-Host "OK: manage-certificates"
    Disconnect-XenServer -Session $session
}

function Get-SelfSignedCertPem {
    <#
    .SYNOPSIS
        A throwaway self-signed certificate and private key (PEM).
    .DESCRIPTION
        .NET creates the key and certificate itself (CertificateRequest, .NET Framework 4.7.2 and later), so
        no external tool is needed on either PowerShell. Writing them as PEM differs: PowerShell 7 (.NET 7+)
        exports the key directly; Windows PowerShell 5.1 (.NET Framework) has no PEM export, so the key is
        encoded from its parameters (ConvertTo-Pkcs8Pem).
    #>
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        "CN=sdk-example", $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $cert = $req.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1), [DateTimeOffset]::UtcNow.AddDays(365))
    $certPem = ConvertTo-Pem -Label 'CERTIFICATE' -Der $cert.RawData
    $keyPem = if ($PSVersionTable.PSEdition -eq 'Core') { $rsa.ExportPkcs8PrivateKeyPem() } else { ConvertTo-Pkcs8Pem -Rsa $rsa }
    return $certPem, $keyPem
}

function ConvertTo-Pem {
    <#
    .SYNOPSIS
        DER bytes as PEM: base64 in 64-character lines between BEGIN/END lines.
    #>
    param([string]$Label, [byte[]]$Der)
    $lines = [Convert]::ToBase64String($Der) -split '(.{64})' | Where-Object { $_ }
    "-----BEGIN $Label-----`n" + ($lines -join "`n") + "`n-----END $Label-----`n"
}

function ConvertTo-Pkcs8Pem {
    <#
    .SYNOPSIS
        An RSA private key as PKCS#8 PEM ("BEGIN PRIVATE KEY"), encoded from its parameters.
    .DESCRIPTION
        For Windows PowerShell 5.1, whose .NET Framework can't export a key as PKCS#8. The key is a DER
        PrivateKeyInfo: version 0, the rsaEncryption algorithm, and the PKCS#1 RSAPrivateKey (version 0, n, e,
        d, p, q, d mod (p-1), d mod (q-1), q^-1 mod p) as an OCTET STRING.
    #>
    param([System.Security.Cryptography.RSA]$Rsa)
    function Get-Der([byte]$Tag, [byte[]]$Value) {
        $length = $Value.Length
        if ($length -lt 0x80) { $head = @($Tag, [byte]$length) }
        else {
            $lengthBytes = @()
            while ($length -gt 0) { $lengthBytes = @([byte]($length -band 0xff)) + $lengthBytes; $length = $length -shr 8 }
            $head = @($Tag, [byte](0x80 + $lengthBytes.Count)) + $lengthBytes
        }
        [byte[]](@($head) + @($Value))
    }
    function Get-DerInteger([byte[]]$BigEndian) {
        # An unsigned big-endian number: drop leading zeros, then add one back if the top bit is set.
        $i = 0
        while ($i -lt $BigEndian.Length - 1 -and $BigEndian[$i] -eq 0) { $i++ }
        $value = @($BigEndian[$i..($BigEndian.Length - 1)])
        if ($value[0] -ge 0x80) { $value = @([byte]0) + $value }
        Get-Der 0x02 $value
    }
    $p = $Rsa.ExportParameters($true)
    $version = [byte[]](0x02, 0x01, 0x00)
    $rsaKey = Get-Der 0x30 ([byte[]](@($version) + (@($p.Modulus, $p.Exponent, $p.D, $p.P, $p.Q, $p.DP, $p.DQ,
        $p.InverseQ) | ForEach-Object { Get-DerInteger $_ })))
    # SEQUENCE { OID 1.2.840.113549.1.1.1 (rsaEncryption), NULL }
    $algorithm = [byte[]](0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00)
    $privateKeyInfo = Get-Der 0x30 ([byte[]](@($version) + @($algorithm) + @(Get-Der 0x04 $rsaKey)))
    ConvertTo-Pem -Label 'PRIVATE KEY' -Der $privateKeyInfo
}
```

<details><summary>Example output</summary>

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
    echo "Certificates:   $(count_csv "$(remote_xe certificate-list --minimal)")"

    # A real, generated self-signed certificate, not a placeholder string: xapi decodes whatever is handed
    # to pool-install-trusted-certificate/host-server-certificate-install as PEM and rejects anything that
    # isn't a well-formed certificate (INVALID_VALUE). filename=/certificate=/private-key= are local files
    # xe uploads itself, the same convention vm-export/vm-import already use in this script.
    local before after
    # Not local: the EXIT trap below reads them after this function has returned.
    certfile=cli-example-cert.pem keyfile=cli-example-key.pem
    rm -f "$certfile" "$keyfile"
    self_signed_cert "$certfile" "$keyfile"
    # However the rest of this goes, don't leave the generated cert/key lying around.
    trap 'rm -f "$certfile" "$keyfile"' EXIT

    # pool-install-trusted-certificate/pool-uninstall-trusted-certificate are the current API; the
    # deprecated pool-*-ca-certificate pair (by name, not by uuid) is superseded by this one.
    # ca=true: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
    before=$(remote_xe certificate-list --minimal)
    remote_xe pool-install-trusted-certificate filename="$certfile" ca=true
    after=$(remote_xe certificate-list --minimal)
    echo "After CA add:   $(count_csv "$after")"
    cert_uuid=""
    for c in $(each_csv "$after"); do
        case ",$before," in *",$c,"*) ;; *) cert_uuid=$c ;; esac
    done
    # Uninstall the trusted CA certificate however the rest of this goes, or it outlives this example.
    trap 'remote_xe_try pool-uninstall-trusted-certificate certificate-uuid=$cert_uuid; rm -f "$certfile" "$keyfile"' EXIT

    # Actually replace the host's own TLS identity with a real certificate (what this workflow's name
    # promises, beyond CA trust), then reset it back to a fresh self-signed one.
    remote_xe host-server-certificate-install uuid=$h certificate="$certfile" private-key="$keyfile"
    echo "Host certificate replaced with a real, generated certificate."
    remote_xe host-reset-server-certificate uuid=$h
    echo "Host certificate reset (a fresh self-signed identity)."

    remote_xe pool-uninstall-trusted-certificate certificate-uuid=$cert_uuid
    rm -f "$certfile" "$keyfile"
    trap - EXIT
    echo "After CA remove:$(count_csv "$(remote_xe certificate-list --minimal)")"

    # Separately from which certificates exist: whether the pool actually CHECKS the ones its members
    # present to each other. There is no matching disable - a pool that could be talked out of verifying
    # would not be verifying - and the enable is idempotent, so this is safe to repeat.
    p=$(first_csv "$(remote_xe pool-list --minimal)")
    echo "TLS verification: $(remote_xe pool-param-get uuid=$p param-name=tls-verification-enabled)"
    remote_xe pool-enable-tls-verification
    echo "  after enabling: $(remote_xe pool-param-get uuid=$p param-name=tls-verification-enabled)"
    ok manage-certificates
}

# A throwaway self-signed certificate and private key (PEM). bash has no native crypto library, so
# shell out to openssl for this.
self_signed_cert() {
    local certfile=$1 keyfile=$2
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$keyfile" -out "$certfile" \
        -days 365 -subj /CN=sdk-example 2>/dev/null
}
```

<details><summary>Example output</summary>

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

    try:
        # Actually replace the host's own TLS identity with a real certificate (what this workflow's
        # name promises, beyond CA trust), then reset it back to a fresh self-signed one.
        session.xenapi.host.install_server_certificate(host_ref, cert_pem, key_pem, "")
        print("Host certificate replaced with a real, generated certificate.")
        session.xenapi.host.reset_server_certificate(host_ref)
        print("Host certificate reset (a fresh self-signed identity).")
    finally:
        # Uninstall the trusted CA certificate however the above went, or it outlives this example.
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

<details><summary>Example output</summary>

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

    try
    {
        // Actually replace the host's own TLS identity with a real certificate (what this workflow's
        // name promises, beyond CA trust), then reset it back to a fresh self-signed one.
        Host.install_server_certificate(session, hostRef, certPem, keyPem, "");
        Console.WriteLine("Host certificate replaced with a real, generated certificate.");
        Host.reset_server_certificate(session, hostRef);
        Console.WriteLine("Host certificate reset (a fresh self-signed identity).");
    }
    finally
    {
        // Uninstall the trusted CA certificate however the above went, or it outlives this example.
        Pool.uninstall_trusted_certificate(session, poolRef, certRef);
    }
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
```

<details><summary>Example output</summary>

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
	defer session.Logout()
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
	certUninstalled := false
	defer func() {
		// Uninstall the trusted CA certificate however the next part went, or it outlives this example.
		if !certUninstalled {
			check(xenapi.Pool.UninstallTrustedCertificate(session, poolRef, certRef))
		}
	}()

	// Actually replace the host's own TLS identity with a real certificate (beyond CA trust), then
	// reset it back to a fresh self-signed one, as before.
	check(xenapi.Host.InstallServerCertificate(session, hosts[0], certPEM, keyPEM, ""))
	fmt.Println("Host certificate replaced with a real, generated certificate.")
	check(xenapi.Host.ResetServerCertificate(session, hosts[0]))
	fmt.Println("Host certificate reset (a fresh self-signed identity).")

	check(xenapi.Pool.UninstallTrustedCertificate(session, poolRef, certRef))
	certUninstalled = true
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

<details><summary>Example output</summary>

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
        String certPem = certAndKey[0];
        String keyPem = certAndKey[1];

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

        try {
            // Actually replace the host's own TLS identity with a real certificate (what this workflow's
            // name promises, beyond CA trust), then reset it back to a fresh self-signed one.
            host.installServerCertificate(conn, certPem, keyPem, "");
            System.out.println("Host certificate replaced with a real, generated certificate.");
            host.resetServerCertificate(conn);
            System.out.println("Host certificate reset (a fresh self-signed identity).");
        } finally {
            // Uninstall the trusted CA certificate however the above went, or it outlives this example.
            pool.uninstallTrustedCertificate(conn, certRef);
        }
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
            if (code != 0) throw new IllegalStateException("openssl failed (" + code + "): " + output);
            String certPem = java.nio.file.Files.readString(certFile.toPath());
            String keyPem = java.nio.file.Files.readString(keyFile.toPath());
            return new String[]{certPem, keyPem};
        } finally {
            java.nio.file.Files.deleteIfExists(keyFile.toPath());
            java.nio.file.Files.deleteIfExists(certFile.toPath());
        }
    }
}
```

<details><summary>Example output</summary>

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
