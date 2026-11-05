function Invoke-ConfigureHa {
    <#
    .SYNOPSIS
        Configure high availability.
    .DESCRIPTION
        Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many host
        failures the pool can tolerate, enable HA, then disable it again.
    .EXAMPLE
        Invoke-ConfigureHa -Url https://xenserver -UserName root -Password $password -HeartbeatSrName 'Shared NFS'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$HeartbeatSrName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    # The HA heartbeat statefile needs a shared SR. Confirm the chosen SR can host it.
    $sr = Get-XenSR -Name $HeartbeatSrName | Where-Object { $_.shared } | Select-Object -First 1
    if (-not $sr) { throw "No shared SR named '$HeartbeatSrName' was found." }
    Write-Host "Heartbeat SR:  $($sr.name_label)"
    $sr | Invoke-XenSR -XenAction AssertCanHostHaStatefile

    # What HA does per VM. The restart priority decides which guests come back first after a host
    # failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
    $guest = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot
    } | Select-Object -First 1

    # How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those: a target
    # computed with none protected can be too high, and protecting a VM afterwards then fails
    # HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN. The configuration maps VM references (XenRef objects - a ref
    # string fails to cast) to restart priorities.
    $guestRef = [XenAPI.XenRef[XenAPI.VM]]::Create($guest.opaque_ref)
    $ntol = $pool | Invoke-XenPool -XenAction HaComputeHypotheticalMaxHostFailuresToTolerate `
        -Configuration @{ $guestRef = "restart" } -PassThru
    Write-Host "Max failures:  $ntol"
    $pool | Set-XenPool -HaHostFailuresToTolerate $ntol

    $pool | Invoke-XenPool -XenAction EnableHa -HeartbeatSrs @($sr) -Configuration @{}
    try {
        Write-Host "HA enabled:    $((Get-XenPool | Select-Object -First 1).ha_enabled)"

        $was = $guest.ha_restart_priority
        $guest | Set-XenVM -HaRestartPriority "restart"
        $nowPriority = (Get-XenVM -Ref $guest.opaque_ref).ha_restart_priority
        Write-Host "$($guest.name_label) priority: '$was' -> '$nowPriority'"
        $guest | Set-XenVM -HaRestartPriority $was

        # And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
        # failure HA should undo, or an administrator's intent it should respect?
        $internal = (Get-XenPool -Ref $pool.opaque_ref).ha_reboot_vm_on_internal_shutdown
        Write-Host "Restart on internal shutdown: $internal"
    }
    finally {
        # Turn HA back off however the above went: left on, it blocks host reboots, coordinator
        # changes and more (HA_IS_ENABLED, HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN).
        $pool | Invoke-XenPool -XenAction DisableHa
    }
    Write-Host "HA enabled:    $((Get-XenPool | Select-Object -First 1).ha_enabled)"
    Write-Host "OK: configure-ha"
    $session | Disconnect-XenServer
}
