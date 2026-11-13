function Invoke-ManageSrLifecycle {
    <#
    .SYNOPSIS
        Detach, reattach and forget storage.
    .DESCRIPTION
        Take a storage repository offline and bring it back: disconnect it from every host, reconnect and
        rescan it, then disconnect it once more and forget it for good.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$NfsServer = "192.0.2.10",
        [string]$NfsPath = "/export/spare"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # There is no "detach" call on an SR. A shared SR is joined to each host by one PBD - a physical
    # block device - and detaching the SR means unplugging every one of them. That is why an SR can be
    # attached on some hosts and not others, and why a repair action exists at all: it plugs back the
    # PBDs that are missing.
    $xenHost = Get-XenHost | Select-Object -First 1
    $sr = New-XenSR -XenHost $xenHost -PhysicalSize 0 `
        -DeviceConfig @{ server = $NfsServer; serverpath = $NfsPath; nfsversion = "3" } `
        -NameLabel "sdk-example-lifecycle" -NameDescription "SR used by the SDK lifecycle example" `
        -Type "nfs" -ContentType "user" -Shared $true -PassThru

    $pbds = @($sr.PBDs | ForEach-Object { Get-XenPBD -Ref $_ })
    Write-Host ("{0}: connected on {1} of {2} host(s)" -f
        $sr.name_label, (Measure-AttachedPbd $pbds), $pbds.Count)

    $pbds | Invoke-XenPBD -XenAction Unplug
    Write-Host ("  detached:   connected on {0} host(s)" -f (Measure-AttachedPbd $pbds))

    # Plugging them back is exactly what a repair does.
    $pbds | Invoke-XenPBD -XenAction Plug
    Write-Host ("  reattached: connected on {0} host(s)" -f (Measure-AttachedPbd $pbds))

    $sr | Invoke-XenSR -XenAction Scan
    Write-Host ("  rescanned:  {0} disk(s)" -f (Get-XenSR -Ref $sr).VDIs.Count)

    # Forgetting drops the pool's record of the SR but leaves the storage itself untouched, so the same
    # export can be introduced again later. Detach before forgetting: a connected SR is still in use.
    $pbds | Invoke-XenPBD -XenAction Unplug
    $sr | Invoke-XenSR -XenAction Forget
    Write-Host "  forgotten"
    Write-Host "OK: manage-sr-lifecycle"
    $session | Disconnect-XenServer
}

function Measure-AttachedPbd {
    <#
    .SYNOPSIS
        How many of these connections are currently live.
    .DESCRIPTION
        Re-read each one: the cached records were fetched before the plug state changed.
    #>
    param($Pbds)
    @($Pbds | Where-Object { (Get-XenPBD -Ref $_).currently_attached }).Count
}
