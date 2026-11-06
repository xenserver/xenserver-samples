function Invoke-ReconnectSrStorage {
    <#
    .SYNOPSIS
        Point an SR at moved storage.
    .DESCRIPTION
        When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an
        SR cannot be edited, so unplug each one, recreate it with the new settings and plug it back.

        Each host reaches an SR through a PBD, whose device_config (server, path, target, ...) says where
        the storage is. A PBD's device_config is fixed when it is created, so changing it means unplugging
        the PBD, destroying it, and creating and plugging a new one with the updated settings, host by host.
        The SR and its disks are untouched throughout. Every PBD has to be unplugged first, which needs every
        VM using the SR to be shut down. This example creates an NFS SR on NfsServer:NfsPath to work on, and
        forgets it again at the end; NewNfsServer defaults to NfsServer, which reconnects the SR to the same
        storage.
    .EXAMPLE
        Invoke-ReconnectSrStorage -Url https://xenserver -UserName root -Password $password -NfsServer 192.0.2.10 -NfsPath /export/spare -NewNfsServer 192.0.2.11
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$NfsServer = "192.0.2.10",
        [string]$NfsPath = "/export/spare",
        [string]$NewNfsServer
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    if (-not $NewNfsServer) { $NewNfsServer = $NfsServer }

    $xenHost = Get-XenHost | Select-Object -First 1
    $sr = New-XenSR -XenHost $xenHost -PhysicalSize 0 `
        -DeviceConfig @{ server = $NfsServer; serverpath = $NfsPath; nfsversion = "3" } `
        -NameLabel "sdk-example-moved-storage" -NameDescription "SR used by the SDK reconnect example" `
        -Type "nfs" -ContentType "user" -Shared $true -PassThru
    try {
        $pbds = @($sr.PBDs | ForEach-Object { Get-XenPBD -Ref $_ })
        $pbds | Invoke-XenPBD -XenAction Unplug

        foreach ($pbd in $pbds) {
            $deviceConfig = @{} + $pbd.device_config
            $deviceConfig.server = $NewNfsServer
            Remove-XenPBD -Ref $pbd
            $replacement = New-XenPBD -XenHost $pbd.host -SR $sr -DeviceConfig $deviceConfig -OtherConfig @{} -PassThru
            $replacement | Invoke-XenPBD -XenAction Plug
            Write-Host ("{0}: now reaches {1}:{2}" -f
                (Get-XenHost -Ref $pbd.host).name_label, $deviceConfig.server, $deviceConfig.serverpath)
        }
    }
    finally {
        # Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
        Invoke-DetachAndForgetSr -Ref $sr
    }
    Write-Host "OK: reconnect-sr-storage"
    $session | Disconnect-XenServer
}
