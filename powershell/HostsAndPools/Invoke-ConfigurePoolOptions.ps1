function Invoke-ConfigurePoolOptions {
    <#
    .SYNOPSIS
        Configure pool options.
    .DESCRIPTION
        Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and
        memory-migration compression — then put them back.
    .EXAMPLE
        Invoke-ConfigurePoolOptions -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    # These are plain pool settings, each a single field. Read them, change them, put them back.
    $before = [ordered]@{
        "live patching disabled" = $pool.live_patching_disabled
        "IGMP snooping"          = $pool.igmp_snooping_enabled
        "migration compression"  = $pool.migration_compression
    }
    foreach ($k in $before.Keys) { Write-Host ("  {0,-22} {1}" -f $k, $before[$k]) }

    # Live patching applies host updates without a reboot; disabling it forces the reboot.
    $pool | Set-XenPool -LivePatchingDisabled (-not $before["live patching disabled"])
    # IGMP snooping keeps multicast off ports that did not ask for it.
    $pool | Set-XenPool -IgmpSnoopingEnabled (-not $before["IGMP snooping"])
    # Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
    $pool | Set-XenPool -MigrationCompression (-not $before["migration compression"])

    $after = Get-XenPool -Ref $pool.opaque_ref
    Write-Host "after changing:"
    Write-Host ("  {0,-22} {1}" -f "live patching disabled", $after.live_patching_disabled)
    Write-Host ("  {0,-22} {1}" -f "IGMP snooping", $after.igmp_snooping_enabled)
    Write-Host ("  {0,-22} {1}" -f "migration compression", $after.migration_compression)

    $pool | Set-XenPool -LivePatchingDisabled $before["live patching disabled"]
    $pool | Set-XenPool -IgmpSnoopingEnabled $before["IGMP snooping"]
    $pool | Set-XenPool -MigrationCompression $before["migration compression"]
    Write-Host "  restored"
    Write-Host "OK: configure-pool-options"
    $session | Disconnect-XenServer
}
