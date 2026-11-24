function Invoke-ApplyUpdate {
    <#
    .SYNOPSIS
        Apply updates from the CDN.
    .DESCRIPTION
        Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator,
        unless you name another - then act on that host's post-update guidance.
    .EXAMPLE
        Invoke-ApplyUpdate -Url https://xenserver -UserName root -Password $password `
            -RepoUrl https://repo.ops.xenserver.com/xs9 -SourceUrl https://repo-src.ops.xenserver.com/xs9
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$SourceUrl,
        [string]$HostName = ""
    )
    # The documentation asks for the coordinator to be updated before any other host, so update it
    # first, then run this again naming each of the others - or use Invoke-RollingPoolUpdate to do the
    # whole pool in one go. Connect-UpdateRepository checks that HA and Workload Balancing are off and
    # attaches a throwaway update repository, which pool.sync_updates needs; it is forgotten again
    # afterwards. Invoke-HostUpdate does the rest: evacuating the host first if that turns out to be
    # needed, acting on its post-update guidance, and returning it to service.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    if ($HostName) {
        $hosts = @(Get-XenHost -Name $HostName)
        if ($hosts.Count -ne 1) {
            throw "expected one host named '$HostName', found $($hosts.Count)"
        }
        $xenHost = $hosts[0]
    }
    else {
        $xenHost = Get-XenHost -Ref $pool.master
    }
    # Before changing anything, stop if a host or VM still has mandatory guidance pending from an earlier
    # update.
    Assert-NoPendingGuidance

    $attached = Connect-UpdateRepository -Session $session -Pool $pool -RepoUrl $RepoUrl -SourceUrl $SourceUrl
    try {
        # Sync the pool's update metadata; -PassThru returns the hash identifying the synced set.
        $hash = $pool | Invoke-XenPool -XenAction SyncUpdates -PassThru
        Write-Host "Synced updates; hash length $($hash.Length)"
        $session = Invoke-HostUpdate -Session $session -Url $Url -UserName $UserName -Password $Password `
            -XenHost $xenHost -Hash $hash -Label "$($xenHost.name_label): "
    }
    finally {
        Disconnect-UpdateRepository -Pool $pool -Attached $attached
    }
    # Restarting a VM to pick the update up is its owner's call: report what is left.
    Write-VmGuidance
    Write-Host "OK: apply-update"
    $session | Disconnect-XenServer
}
