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

    # Actually replace the host's own TLS identity with a real certificate (what this workflow's name
    # promises, beyond CA trust), then reset it back to a fresh self-signed one.
    Invoke-XenHost -Ref $xenHost -XenAction InstallServerCertificate `
        -Certificate $certPem -PrivateKey $keyPem -CertificateChain ''
    Write-Host "Host certificate replaced with a real, generated certificate."

    Invoke-XenHost -Ref $xenHost -XenAction ResetServerCertificate
    Write-Host "Host certificate reset (a fresh self-signed identity)."

    Invoke-XenPool -Ref $pool -XenAction UninstallTrustedCertificate -Certificate $cert
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
