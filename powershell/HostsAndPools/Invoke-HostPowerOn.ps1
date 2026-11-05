function Invoke-HostPowerOn {
    <#
    .SYNOPSIS
        Configure host power on.
    .DESCRIPTION
        Set a host's out-of-band power-on mode and credentials, then read them back.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1

    # Mode and config travel together — host.set_power_on_mode takes both in one call, because the
    # config carries the out-of-band credentials the mode needs. The module exposes only
    # Set-XenHost -PowerOnMode (no -PowerOnConfig), so this calls the method directly over JSON-RPC,
    # the same way the events example does for the missing event cmdlet. Still pure PowerShell: no
    # [XenAPI.*]:: statics, and Connect has already trusted the server's certificate.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
    # modes were removed from the real power-on plugin and fail the moment host.power_on is actually
    # called ("{mode} script has been removed").
    Invoke-XenMethod -Session $session -Method 'host.set_power_on_mode' -Params @(
        $xenHost.opaque_ref, 'wake-on-lan', @{})
    $updated = Get-XenHost -Ref $xenHost.opaque_ref
    Write-Host "Power-on mode:  $($updated.power_on_mode)"
    foreach ($k in ($updated.power_on_config.Keys | Sort-Object)) {
        Write-Host "  $k = $($updated.power_on_config[$k])"
    }

    Invoke-XenMethod -Session $session -Method 'host.set_power_on_mode' -Params @($xenHost.opaque_ref, '', @{})
    Write-Host "OK: host-power-on"
    Disconnect-XenServer -Session $session
}
