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
    Write-Host "OK: sr-usage"
    $session | Disconnect-XenServer
}
