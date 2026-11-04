function Invoke-ApplyUpdate {
    <#
    .SYNOPSIS
        Apply updates from the CDN.
    .DESCRIPTION
        Sync the pool's update metadata from the CDN and apply it to every host, then read each host's
        post-update reboot guidance.
    .EXAMPLE
        Invoke-ApplyUpdate -Url https://xenserver -UserName root -Password $password `
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
    # pool.sync_updates needs at least one repository with Update enabled (NO_REPOSITORY_ENABLED
    # otherwise) - introduce and attach a throwaway one, and forget it again afterwards. Applying a
    # batch whose mandatory guidance needs an evacuation fails with HOST_EVACUATION_IS_REQUIRED unless
    # the host's resident VMs are moved off first; handle that rather than assuming an update batch
    # never asks for one. Only call Reboot/RestartAgent when the *returned* pending guidance actually
    # contains "reboot_host"/"restart_toolstack" (modern xapi, >=23.18.0, never auto-reboots - it only
    # records guidance) - not unconditionally after every apply.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    $repos = @(New-UpdateRepositories -Session $session -RepoUrl $RepoUrl -SourceUrl $SourceUrl)
    # Remember the pool's own repositories, to put them back afterwards.
    $previous = @((Get-XenPool -Ref $pool.opaque_ref).repositories | ForEach-Object { $_.opaque_ref })
    $pool | Set-XenPool -Repositories @($repos | ForEach-Object { $_.opaque_ref })
    try {
        # Sync the pool's update metadata; -PassThru returns the hash identifying the synced set.
        $hash = $pool | Invoke-XenPool -XenAction SyncUpdates -PassThru
        Write-Host "Synced updates; hash length $($hash.Length)"

        # Apply the synced updates to each host (the hash is the action's -Hash parameter). XenCenter
        # then reads the reboot guidance to decide whether a Rolling Pool Upgrade reboot is needed.
        foreach ($xenHost in Get-XenHost) {
            try {
                $xenHost | Invoke-XenHost -XenAction ApplyUpdates -Hash $hash
            }
            catch {
                $ex = $_.Exception
                while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
                if (-not ($ex -and $ex.ErrorDescription -and $ex.ErrorDescription[0] -eq "HOST_EVACUATION_IS_REQUIRED")) {
                    throw
                }
                Write-Host "  $($xenHost.name_label): needs evacuating first; evacuating and retrying"
                $xenHost | Invoke-XenHost -XenAction Disable
                Invoke-Evacuate -XenHost $xenHost
                $xenHost | Invoke-XenHost -XenAction ApplyUpdates -Hash $hash
                $xenHost | Invoke-XenHost -XenAction Enable
            }
            $guidance = @((Get-XenHost -Ref $xenHost.opaque_ref).pending_guidances)
            Write-Host "  $($xenHost.name_label): applied; pending guidance = [$($guidance -join ', ')]"
            if ($guidance -contains "reboot_host" -or $guidance -contains "restart_toolstack") {
                # As in rolling-pool-update: either restart returns before it has happened, and the
                # coordinator's takes this session with it - so wait for it, reconnecting.
                $key = if ($guidance -contains "reboot_host") { "boot_time" } else { "agent_start_time" }
                $before = (Get-XenHost -Ref $xenHost.opaque_ref).other_config[$key]
                if ($key -eq "boot_time") {
                    $xenHost | Invoke-XenHost -XenAction Reboot
                }
                else {
                    $xenHost | Invoke-XenHost -XenAction RestartAgent
                }
                $session = Wait-ForRestart -Url $Url -UserName $UserName -Password $Password `
                    -HostUuid $xenHost.uuid -Key $key -Before $before
            }
            # apply_updates disables the host while it works (auto_enable: a restart puts it back) - with no
            # restart to do, nothing re-enables it. Return it to service either way.
            Enable-WhenBooted -XenHost $xenHost
        }
    }
    finally {
        $pool | Set-XenPool -Repositories $previous
        $repos | ForEach-Object { $_ | Invoke-XenRepository -XenAction Forget }
    }
    Write-Host "OK: apply-update"
    $session | Disconnect-XenServer
}
