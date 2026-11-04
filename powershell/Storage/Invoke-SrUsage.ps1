function Invoke-SrUsage {
    <#
    .SYNOPSIS
        Storage repository usage.
    .DESCRIPTION
        Report each storage repository's used and total capacity, and rescan one.
    .EXAMPLE
        Invoke-SrUsage -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    Get-XenSR | Sort-Object name_label | Where-Object { $_.physical_size -gt 0 } | ForEach-Object {
        $used = [long]($_.physical_utilisation / 1GB)
        $total = [long]($_.physical_size / 1GB)
        Write-Host "  $($_.name_label): $used / $total GiB used"
    }
    # A rescan refreshes an SR's utilisation from its backend.
    $scanMe = Get-XenSR | Where-Object { $_.physical_size -gt 0 } | Select-Object -First 1
    $scanMe | Invoke-XenSR -XenAction Scan

    # Read caching keeps recently-read blocks in the host's memory. It is switched off per SR by
    # setting o_direct, which asks the storage layer to bypass the cache entirely. Add-XenSR appends
    # one other_config entry as a KeyValuePair; Remove-XenSRProperty drops it again by key.
    $scanMe | Remove-XenSRProperty -OtherConfig "o_direct"
    $scanMe | Add-XenSR -OtherConfig ([System.Collections.Generic.KeyValuePair[string, string]]::new("o_direct", "true"))
    $cachingOff = (Get-XenSR -Ref $scanMe.opaque_ref).other_config["o_direct"] -eq "true"
    Write-Host "  read caching on $($scanMe.name_label): $(if ($cachingOff) { 'off' } else { 'on' })"
    $scanMe | Remove-XenSRProperty -OtherConfig "o_direct"
    Write-Host "OK: sr-usage"
    $session | Disconnect-XenServer
}
