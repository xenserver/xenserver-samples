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
