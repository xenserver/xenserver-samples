function Invoke-RollingPoolUpdate {
    <#
    .SYNOPSIS
        Rolling pool update.
    .DESCRIPTION
        Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
        coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if
        the update asks for that, and return it to service.
    .EXAMPLE
        Invoke-RollingPoolUpdate -Url https://xenserver -UserName root -Password $password `
            -RepoUrl https://repo.ops.xenserver.com/xs9 -SourceUrl https://repo-src.ops.xenserver.com/xs9
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    $hosts = @(Get-XenHost -Ref $pool.master) + @(Get-XenHost | Where-Object { $pool.master -ne $_ })
    # Check first that every host can be emptied: VmsWhichPreventEvacuation names the VMs that could not
    # move anywhere else (for example a VM with a disk on the host's local storage, or a pool with
    # nowhere else to put them) - stop before changing anything if there are any.
    foreach ($xenHost in $hosts) {
        $blocking = Get-XenHostProperty -XenHost $xenHost -XenProperty VmsWhichPreventEvacuation
        if ($blocking.Count -gt 0) {
            $names = ($blocking.Keys | ForEach-Object { (Get-XenVM -Ref $_).name_label }) -join ', '
            throw "$($xenHost.name_label) cannot be evacuated: move or shut down $names first"
        }
    }

    # Connect-UpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
    # update repository, which pool.sync_updates needs; it is forgotten again afterwards.
    $attached = Connect-UpdateRepository -Session $session -Pool $pool -RepoUrl $RepoUrl -SourceUrl $SourceUrl
    try {
        $hash = $pool | Invoke-XenPool -XenAction SyncUpdates -PassThru
        Write-Host "Synced updates; hash length $($hash.Length)"
        # For each host: disable it so nothing new starts there, evacuate it (live-migrating its VMs to
        # the other hosts), and let Invoke-HostUpdate apply the updates, restart the host or its
        # toolstack if the update asks for that, and enable it again. The VMs stay where evacuation put
        # them.
        foreach ($xenHost in $hosts) {
            Write-Host "Updating $($xenHost.name_label): moving its VMs to the rest of the pool"
            $xenHost | Invoke-XenHost -XenAction Disable
            Invoke-Evacuate -XenHost $xenHost
            $session = Invoke-HostUpdate -Session $session -Url $Url -UserName $UserName -Password $Password `
                -XenHost $xenHost -Hash $hash
        }
    }
    finally {
        Disconnect-UpdateRepository -Pool $pool -Attached $attached
    }
    Write-Host "OK: rolling-pool-update"
    $session | Disconnect-XenServer
}
