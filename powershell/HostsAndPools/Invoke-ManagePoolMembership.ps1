function Invoke-ManagePoolMembership {
    <#
    .SYNOPSIS
        Manage pool membership.
    .DESCRIPTION
        List the pool's member hosts and which one coordinates it, promote a different host to coordinator,
        then promote the original back.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    $hosts = Get-XenHost
    $originalRef = $pool.master.opaque_ref
    $original = $hosts | Where-Object { $_.opaque_ref -eq $originalRef }
    Write-Host "Coordinator: $($original.name_label)"
    foreach ($h in $hosts) {
        $tag = if ($h.opaque_ref -eq $originalRef) { " (coordinator)" } else { "" }
        Write-Host "  member: $($h.name_label)$tag"
    }

    # Promote another member. The pool database moves with the role and clients are redirected, so this
    # briefly interrupts management traffic — it does not move any VM.
    $other = $hosts | Where-Object { $_.opaque_ref -ne $originalRef } | Select-Object -First 1
    Invoke-XenPool -Ref $pool.opaque_ref -XenAction DesignateNewMaster -XenHost $other.opaque_ref
    Write-Host "Promoting:   $($other.name_label) (xapi restarts pool-wide; reconnecting)"

    $session = Reconnect-AfterMasterChange -Url $Url -UserName $UserName -Password $Password `
        -NewMasterUuid $other.uuid
    $pool = Get-XenPool | Select-Object -First 1
    Write-Host "Promoted:    $((Get-XenHost -Ref $pool.master.opaque_ref).name_label)"

    # Put it back. Ejecting a member (Pool.eject) is the other half of this surface and is deliberately
    # not shown: it cannot be undone from the pool, because rejoining is initiated by the ejected host.
    Invoke-XenPool -Ref $pool.opaque_ref -XenAction DesignateNewMaster -XenHost $originalRef
    Write-Host "Restoring:   $($original.name_label) (reconnecting again)"

    $session = Reconnect-AfterMasterChange -Url $Url -UserName $UserName -Password $Password `
        -NewMasterUuid $original.uuid
    $pool = Get-XenPool | Select-Object -First 1
    Write-Host "Restored:    $((Get-XenHost -Ref $pool.master.opaque_ref).name_label)"

    Write-Host "OK: manage-pool-membership"
    $session | Disconnect-XenServer
}

function Reconnect-AfterMasterChange {
    <#
    .SYNOPSIS
        Wait out a pool-wide xapi restart (pool.designate_new_master) and reconnect.
    .DESCRIPTION
        designate_new_master returns BEFORE the change: for a while the old coordinator still answers, and
        still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not enough
        - keep reconnecting until the pool names the new coordinator (by uuid; Connect-Example follows
        HOST_IS_SLAVE to wherever the coordinator now is). That can take minutes.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$NewMasterUuid,
        [int]$TimeoutSeconds = 600,
        [int]$IntervalSeconds = 5
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
            $master = (Get-XenPool | Select-Object -First 1).master
            # The new coordinator answers before the pool has settled - calls made too soon fail
            # (HANDLE_INVALID on the operation's own task) - so also wait for every host to be back,
            # live and enabled.
            $settled = (Get-XenHost -Ref $master.opaque_ref).uuid -eq $NewMasterUuid -and
                -not (Get-XenHost | Where-Object {
                    -not $_.enabled -or -not (Get-XenHostMetrics -Ref $_.metrics.opaque_ref).live
                })
            if ($settled) { return $session }
            $session | Disconnect-XenServer
            $lastError = "the pool has not settled under the new coordinator"
        }
        catch { $lastError = $_ }
        Start-Sleep -Seconds $IntervalSeconds
    }
    throw "the pool did not come back after the master change: $lastError"
}
