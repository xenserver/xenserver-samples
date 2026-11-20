function Invoke-ManageSshAccess {
    <#
    .SYNOPSIS
        Manage SSH access.
    .DESCRIPTION
        Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it again
        — the pool-level call fans out to every host.
    .EXAMPLE
        Invoke-ManageSshAccess -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool
    # Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
    $before = @(Get-XenHost | ForEach-Object {
        [pscustomobject]@{ Ref = $_; Enabled = $_.ssh_enabled; Timeout = $_.ssh_enabled_timeout } })

    # Timed access is the point: set the timeout first and the server stamps an expiry when SSH is
    # enabled, so a window opened for troubleshooting closes itself. set_ssh_enabled_timeout is itself a
    # pool-wide fan-out call, exactly like enable_ssh/disable_ssh - no need to loop hosts for it either.
    $pool | Set-XenPool -SshEnabledTimeout 3600

    # The pool action fans out to every host, so there is no need to loop for the enable itself.
    Invoke-XenPool -Pool $pool -XenAction EnableSsh
    Get-XenHost | ForEach-Object {
        Write-Host "$($_.name_label): ssh enabled=$($_.ssh_enabled), expires $($_.ssh_expiry.ToString('yyyyMMddTHH:mm:ssZ'))"
    }

    Invoke-XenPool -Pool $pool -XenAction DisableSsh
    Write-Host ("After disable: " + ((Get-XenHost | ForEach-Object { "$($_.name_label)=$($_.ssh_enabled)" }) -join ', '))

    foreach ($h in $before) {
        # first: enabling stamps the expiry from it
        Get-XenHost -Ref $h.Ref | Set-XenHost -SshEnabledTimeout $h.Timeout
        if ($h.Enabled) { Invoke-XenHost -Ref $h.Ref -XenAction EnableSsh }
    }
    Write-Host "OK: manage-ssh-access"
    $session | Disconnect-XenServer
}
