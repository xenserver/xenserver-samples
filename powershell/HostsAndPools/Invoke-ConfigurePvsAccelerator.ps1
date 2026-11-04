function Invoke-ConfigurePvsAccelerator {
    <#
    .SYNOPSIS
        Configure PVS Accelerator.
    .DESCRIPTION
        Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS
        server, put a read cache on each host's local storage, accelerate a VM by proxying its first NIC,
        then forget the site — which cascades to everything hanging off it.
    .EXAMPLE
        Invoke-ConfigurePvsAccelerator -Url https://xenserver -UserName root -Password $password -VmName 'db-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # Check the VM first, before creating anything: it needs a NIC for the proxy to sit on. It need not
    # be running - a proxy on a halted VM just reports "stopped" until it starts.
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    # A proxy may only sit on the VM's LOWEST-numbered NIC, so sort by device rather than taking the
    # first VIF — the list comes back in creation order, which is the same thing only by luck.
    $vif = $vm.VIFs | ForEach-Object { Get-XenVIF -Ref $_.opaque_ref } |
        Sort-Object { [int]$_.device } | Select-Object -First 1
    if (-not $vif) { throw "$VmName has no network interface to accelerate" }
    # ... and one that no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT).
    $existing = Get-XenPVSProxy | Where-Object { $_.VIF.opaque_ref -eq $vif.opaque_ref } | Select-Object -First 1
    if ($existing) {
        throw "$VmName is already accelerated by site '$((Get-XenPVSSite -Ref $existing.site.opaque_ref).name_label)'"
    }

    # PVS_site.introduce and PVS_server.introduce are CONSTRUCTORS, and every parameter set of
    # Invoke-XenPVSSite / Invoke-XenPVSServer identifies an object that ALREADY EXISTS (-PVSSite / -Ref /
    # -Uuid / -Name). Introduce is in the -XenAction enum, but there is no way to call it: name an object
    # and it goes looking for one that isn't there yet; name none and PowerShell cannot choose between
    # four sets, so it fails at binding with AmbiguousParameterSet before the call is even attempted.
    # Same shape as Cluster.pool_create in configure-clustering — so, same answer: call the method over
    # JSON-RPC. Still pure PowerShell; no [XenAPI.*]:: statics.
    $site = Invoke-XenMethod -Session $session -Method 'PVS_site.introduce' `
        -Params @('sdk-example-pvs', 'Created by the SDK examples', '')
    Invoke-XenMethod -Session $session -Method 'PVS_server.introduce' `
        -Params @(@('203.0.113.90'), 6910, 6930, $site) | Out-Null

    # The read cache must be on LOCAL storage: keeping reads off the network is the point, so a cache on
    # a shared SR would defeat it and the server rejects one. New-XenPVSCacheStorage is a real cmdlet.
    foreach ($xenHost in Get-XenHost) {
        $local = Get-XenPBD | Where-Object { $_.host.opaque_ref -eq $xenHost.opaque_ref } |
            ForEach-Object { Get-XenSR -Ref $_.SR.opaque_ref } |
            Where-Object { -not $_.shared -and $_.content_type -ne 'iso' -and $_.type -ne 'udev' } |
            Select-Object -First 1
        if (-not $local) { continue }
        New-XenPVSCacheStorage -XenHost $xenHost.opaque_ref -SR $local.opaque_ref -Site $site `
            -Size 10GB | Out-Null
    }

    $proxy = New-XenPVSProxy -Site $site -VIF $vif.opaque_ref -PassThru

    $record = Get-XenPVSSite -Ref $site
    Write-Host "Site '$($record.name_label)' with $($record.cache_storage.Count) cache(s) and $($record.servers.Count) server(s)"
    # "caching" means it is really accelerating: a site with no cache reports "initialised", and a proxy
    # on a VM whose NIC is unplugged reports "stopped".
    Write-Host "  $($vm.name_label): $($proxy.status)"

    # Forgetting the site only cascades its cache storage - a running proxy or a server it still has
    # makes forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down ourselves
    # first, in the same order every real PVS teardown uses. (Cache storage doesn't need a separate
    # call - forget cascades it correctly.)
    Remove-XenPVSProxy -Ref $proxy.opaque_ref
    foreach ($serverRef in (Get-XenPVSSite -Ref $site).servers) {
        Invoke-XenPVSServer -Ref $serverRef.opaque_ref -XenAction Forget
    }
    Invoke-XenPVSSite -Ref $site -XenAction Forget
    Write-Host "OK: configure-pvs-accelerator"
    $session | Disconnect-XenServer
}
