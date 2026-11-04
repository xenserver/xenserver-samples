# Connecting to XenServer is a little more involved than Connect-XenServer on its own:
#   * a server presents a self-signed certificate on first contact, so you accept it
#     (-NoWarnCertificates / -NoWarnNewCertificates), and -SetDefaultSession lets the other
#     Get-Xen*/Invoke-Xen* cmdlets use the session implicitly; and
#   * if you point it at a pool *member* rather than the coordinator, the login is rejected with
#     HOST_IS_SLAVE naming the coordinator - so you reconnect to that address (exactly what XenCenter
#     does for you when you add a member server). Connect-Example wraps both concerns:
#
#     $session = Connect-Example -Url https://xenserver -UserName root -Password $password
#     <# ... call cmdlets ... #>
#     $session | Disconnect-XenServer

# --- connect ---
function Connect-Example {
    # A thin, reusable wrapper around the connect handshake described above, so each example can stay
    # focused on the task. Follows the pool-member -> coordinator redirect (HOST_IS_SLAVE).
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    # Accepting the certificate in Connect-XenServer covers the module's cmdlets, and on Windows PowerShell
    # 5.1 Invoke-RestMethod/Invoke-WebRequest as well. PowerShell 7's web cmdlets keep their own trust, so
    # extend the same acceptance to them for the examples that talk to the host over plain HTTP(S).
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $global:PSDefaultParameterValues['Invoke-RestMethod:SkipCertificateCheck'] = $true
        $global:PSDefaultParameterValues['Invoke-WebRequest:SkipCertificateCheck'] = $true
    }
    try {
        return Connect-XenServer -Url $Url -UserName $UserName -Password $Password `
            -NoWarnCertificates -NoWarnNewCertificates -SetDefaultSession -PassThru
    }
    catch {
        # A pool member reports the coordinator's address in the HOST_IS_SLAVE error; reconnect there
        # (assuming the coordinator is up, as XenCenter does when you add a member server).
        $desc = $_.Exception.ErrorDescription
        if ($desc[0] -ne "HOST_IS_SLAVE") { throw }
        return Connect-XenServer -Url "https://$($desc[1])" -UserName $UserName -Password $Password `
            -NoWarnCertificates -NoWarnNewCertificates -SetDefaultSession -PassThru
    }
}
