function Invoke-PvsAccelerator {
    <#
    .SYNOPSIS
        PVS Accelerator inventory.
    .DESCRIPTION
        Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host, size,
        storage), its PVS servers (addresses and streaming port range), and which VMs are accelerated versus
        the whole pool.
    .EXAMPLE
        Invoke-PvsAccelerator -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $sites = @(Get-XenPVSSite)
    if ($sites.Count -eq 0) { Write-Host "No PVS Accelerator sites are configured." }
    foreach ($site in $sites) {
        Write-Host "Site: $($site.name_label)"
        foreach ($csRef in $site.cache_storage) {
            $cs = Get-XenPVSCacheStorage -Ref $csRef.opaque_ref
            $cacheHost = Get-XenHost -Ref $cs.host.opaque_ref
            $sr = Get-XenSR -Ref $cs.SR.opaque_ref
            Write-Host ("  cache:  $($cacheHost.name_label)  $([long]($cs.size / 1GB)) GiB on $($sr.name_label)")
        }
        foreach ($serverRef in $site.servers) {
            $server = Get-XenPVSServer -Ref $serverRef.opaque_ref
            Write-Host ("  server: $($server.addresses -join ', ')  ports $($server.first_port)-$($server.last_port)")
        }
        # Which VMs are accelerated: walk each proxy to its VIF to its VM.
        $accelerated = @{}
        foreach ($proxyRef in $site.proxies) {
            $proxy = Get-XenPVSProxy -Ref $proxyRef.opaque_ref
            $vif = Get-XenVIF -Ref $proxy.VIF.opaque_ref
            $accelerated[$vif.VM.opaque_ref] = $proxy.status
        }
        $guests = Get-XenVM | Where-Object { -not $_.is_control_domain -and -not $_.is_a_template -and -not $_.is_a_snapshot }
        $count = @($guests | Where-Object { $accelerated.ContainsKey($_.opaque_ref) }).Count
        Write-Host "  $count of $(@($guests).Count) VM(s) accelerated"
    }
    Write-Host "OK: pvs-accelerator"
    $session | Disconnect-XenServer
}
