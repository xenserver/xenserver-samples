function Invoke-RollingPoolUpdate {
    <#
    .SYNOPSIS
        Rolling pool update.
    .DESCRIPTION
        Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in
        turn - coordinator first - apply the updates (evacuating its VMs first only if that turns out to be
        needed), reboot if asked to, and re-enable it — host-by-host orchestration.
    .EXAMPLE
        Invoke-RollingPoolUpdate -Url https://xenserver -UserName root -Password $password `
    .EXAMPLE
        -RepoUrl https://repo.ops.xenserver.com/xs9 -SourceUrl https://repo-src.ops.xenserver.com/xs9
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )
    # ApplyUpdates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
    # Workload Balancing to be switched off before you start updating - so check both up front and stop
    # rather than disabling either for you; turn them back on again once the update is done.
    #
    # Needs an enabled update repository the same way apply-update does - introduce and attach a
    # throwaway one, forget it again afterwards. Modern xapi (>=23.18.0) doesn't reboot a host for you:
    # it only records pending_guidances, so only reboot (or restart the toolstack) when the applied
    # batch actually asks for it, and only evacuate a host first if applying without doing so fails
    # with HOST_EVACUATION_IS_REQUIRED - most updates don't need it. Guidance that targets VMs instead
    # of hosts (for example restarting a VM) is not handled here.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    if ($pool.ha_enabled -or $pool.wlb_enabled) {
        throw "HA and Workload Balancing must both be off before updating the pool; disable them, " +
            "run this again, then re-enable them once it finishes"
    }
    $repos = @(New-UpdateRepositories -Session $session -RepoUrl $RepoUrl -SourceUrl $SourceUrl)
    # Remember the pool's own repositories, to put them back afterwards.
    $previous = @((Get-XenPool -Ref $pool.opaque_ref).repositories | ForEach-Object { $_.opaque_ref })
    $pool | Set-XenPool -Repositories @($repos | ForEach-Object { $_.opaque_ref })
    try {
        $hash = $pool | Invoke-XenPool -XenAction SyncUpdates -PassThru
        Write-Host "Synced updates; hash length $($hash.Length)"

        # The rolling pattern: apply -> evacuate and retry only if that turns out to be needed ->
        # reboot (only if asked) -> re-enable, one host at a time, coordinator first.
        $orderedHosts = @($pool.master.opaque_ref) + @(Get-XenHost |
            Where-Object { $_.opaque_ref -ne $pool.master.opaque_ref } | ForEach-Object { $_.opaque_ref })
        foreach ($xenHost in $orderedHosts | ForEach-Object { Get-XenHost -Ref $_ }) {
            Write-Host "Updating $($xenHost.name_label):"
            try {
                $xenHost | Invoke-XenHost -XenAction ApplyUpdates -Hash $hash  # apply the synced updates
            }
            catch {
                $ex = $_.Exception
                while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
                if (-not ($ex -and $ex.ErrorDescription -and $ex.ErrorDescription[0] -eq "HOST_EVACUATION_IS_REQUIRED")) {
                    throw
                }
                Write-Host "  needs evacuating first; evacuating and retrying"
                $xenHost | Invoke-XenHost -XenAction Disable    # stop new VMs landing here
                Invoke-Evacuate -XenHost $xenHost               # move running guests to the rest of the pool
                $xenHost | Invoke-XenHost -XenAction ApplyUpdates -Hash $hash
                $xenHost | Invoke-XenHost -XenAction Enable
            }
            $guidance = @((Get-XenHost -Ref $xenHost.opaque_ref).pending_guidances)
            Write-Host "  applied; pending guidance = [$($guidance -join ', ')]"
            if ($guidance -contains "reboot_host" -or $guidance -contains "restart_toolstack") {
                # Either restart returns before it has happened, and if this host is the coordinator it
                # takes this session with it - so note when the host last started, restart it, and
                # reconnect until it reports a newer start and is live again.
                $key = if ($guidance -contains "reboot_host") { "boot_time" } else { "agent_start_time" }
                $before = $xenHost.other_config[$key]
                if ($key -eq "boot_time") {
                    $xenHost | Invoke-XenHost -XenAction Reboot     # reboot into the updated software
                }
                else {
                    $xenHost | Invoke-XenHost -XenAction RestartAgent
                }
                $session = Wait-ForRestart -Url $Url -UserName $UserName -Password $Password `
                    -HostUuid $xenHost.uuid -Key $key -Before $before
            }
            Enable-WhenBooted -XenHost $xenHost   # return the host to service
        }
    }
    finally {
        $pool | Set-XenPool -Repositories $previous
        $repos | ForEach-Object { $_ | Invoke-XenRepository -XenAction Forget }
    }
    Write-Host "OK: rolling-pool-update"
    $session | Disconnect-XenServer
}
