function Invoke-ReclaimSpace {
    <#
    .SYNOPSIS
        Reclaim freed space on a thin SR.
    .DESCRIPTION
        Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable
        SR, pick a host with a live connection to it, and run the trim operation.
    .EXAMPLE
        Invoke-ReclaimSpace -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
    $trimTypes = @(Get-XenSM | Where-Object { $_.features.ContainsKey("SR_TRIM") } | ForEach-Object { $_.type })
    $sr = Get-XenSR | Where-Object { $_.physical_size -gt 0 -and $trimTypes -contains $_.type } | Select-Object -First 1
    # A host with a currently-attached PBD can reach the SR to run the plugin.
    $pbd = $sr.PBDs | ForEach-Object { Get-XenPBD -Ref $_ } | Where-Object { $_.currently_attached } | Select-Object -First 1
    $xenHost = Get-XenHost -Ref $pbd.host
    $result = $xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin "trim" -Fn "do_trim" -Args @{ sr_uuid = $sr.uuid } -PassThru
    Write-Host "  reclaimed freed space on $($sr.name_label): $result"
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    if ($result.Trim().ToLowerInvariant() -ne "true") { throw "trim plugin returned '$result'" }
    Write-Host "OK: reclaim-space"
    $session | Disconnect-XenServer
}
