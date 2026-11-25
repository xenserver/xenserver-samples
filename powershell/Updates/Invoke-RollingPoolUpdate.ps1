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
    $hosts = Get-HostsCoordinatorFirst
    # Check first, before changing anything, that the update can go through: no host or VM may still have
    # mandatory guidance pending from an earlier update, and every host must be able to empty.
    Assert-NoPendingGuidance
    Assert-HostsCanBeEvacuated -Hosts $hosts

    # Connect-UpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
    # update repository, which pool.sync_updates needs; it is forgotten again afterwards.
    $attached = Connect-UpdateRepository -Session $session -Pool $pool -RepoUrl $RepoUrl -SourceUrl $SourceUrl
    try {
        $hash = $pool | Invoke-XenPool -XenAction SyncUpdates -PassThru
        Write-Host "Synced updates; hash length $($hash.Length)"
        # Update-Hosts updates each host in turn: disable it, evacuate it, apply the updates, restart it or
        # its toolstack if the update asks for that, and enable it again.
        $session = Update-Hosts -Session $session -Url $Url -UserName $UserName -Password $Password `
            -Hosts $hosts -Hash $hash
    }
    finally {
        Disconnect-UpdateRepository -Pool $pool -Attached $attached
    }
    # Restarting a VM to pick the update up is its owner's call: report what is left.
    Write-VmGuidance
    Write-Host "OK: rolling-pool-update"
    $session | Disconnect-XenServer
}
