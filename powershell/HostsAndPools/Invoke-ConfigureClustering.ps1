function Invoke-ConfigureClustering {
    <#
    .SYNOPSIS
        Configure clustering.
    .DESCRIPTION
        Enable the clustering layer that shared block storage needs for thin provisioning, then watch quorum
        as a host leaves the cluster and rejoins it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # Clustering is what shared block storage needs before GFS2 thin provisioning. Run it over a network
    # every host is on - the management network - since corosync is latency-sensitive and a cluster that
    # loses quorum takes its GFS2 storage offline with it.
    $pifs = @(Get-XenPIF)
    $network = Get-XenNetwork -Ref ($pifs | Where-Object { $_.management } | Select-Object -First 1).network.opaque_ref
    $networkPifs = @($pifs | Where-Object { $_.network.opaque_ref -eq $network.opaque_ref })

    $cluster = Get-XenCluster | Select-Object -First 1
    $created = -not $cluster
    if ($created) {
        # Corosync must not lose its network, so each host's PIF on it has to refuse unplugging first:
        # Cluster.pool_create fails PIF_ALLOWS_UNPLUG otherwise. $networkPifs keeps the old settings.
        $networkPifs | ForEach-Object { Set-XenPIF -Ref $_.opaque_ref -DisallowUnplug $true }
        # Invoke-XenCluster's parameter sets are XenObject / Ref / Uuid -- every one of them identifies an
        # EXISTING cluster -- so the module cannot express pool_create, which is a constructor. Same
        # situation as the event API: call it over JSON-RPC (see Invoke-XenMethod in Helpers.ps1).
        $ref = Invoke-XenMethod -Session $session -Method 'Cluster.pool_create' `
            -Params @($network.opaque_ref, 'corosync', 20.0, 1.0)  # seconds, not ms: XS9 refuses 20000
        $cluster = Get-XenCluster -Ref $ref
    }

    Write-Host "Stack:      $($cluster.cluster_stack)"
    Write-Host "Quorate:    $($cluster.is_quorate) ($($cluster.live_hosts)/$($cluster.quorum) needed)"

    # Taking a host out is what a management-interface change does; it can cost quorum.
    $member = Get-XenClusterHost | Select-Object -First 1
    Invoke-XenClusterHost -Ref $member.opaque_ref -XenAction Disable
    Write-Host "One member out, quorate: $((Get-XenCluster | Select-Object -First 1).is_quorate)"

    Invoke-XenClusterHost -Ref $member.opaque_ref -XenAction Enable
    Invoke-XenCluster -Ref $cluster.opaque_ref -XenAction PoolResync
    Write-Host "Resynced,   quorate: $((Get-XenCluster | Select-Object -First 1).is_quorate)"

    # Tidy up a cluster this example created (one that was already there stays), and the PIF settings.
    if ($created) {
        Invoke-XenCluster -Ref $cluster.opaque_ref -XenAction PoolDestroy
        $networkPifs | ForEach-Object { Set-XenPIF -Ref $_.opaque_ref -DisallowUnplug $_.disallow_unplug }
        Write-Host "Cluster removed again."
    }

    Write-Host "OK: configure-clustering"
    $session | Disconnect-XenServer
}
