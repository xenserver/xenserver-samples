function Invoke-RrdMetrics {
    <#
    .SYNOPSIS
        Read RRD performance metrics.
    .DESCRIPTION
        Pull recent host performance samples from the RRD archives over the performance-data HTTP API, parse
        the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space utilisation
        per host).
    .EXAMPLE
        Invoke-RrdMetrics -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # The module ships no RRD cmdlet, so read the last 5 minutes of samples from the rrd_updates HTTP API
    # (the module already trusts the server cert). Legends look like "AVERAGE:host:<uuid>:<datasource>".
    $start = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 300
    $resp = Invoke-RestMethod -Uri "$($session.Url)/rrd_updates?session_id=$($session.opaque_ref)&host=true&start=$start" `
        -Headers @{ accept = 'application/json' }
    $legends = @($resp.meta.legend)

    $peak = @{}
    foreach ($point in $resp.data) {
        for ($k = 0; $k -lt $legends.Count; $k++) {
            $parts = $legends[$k] -split ':'
            if ($parts[1] -eq 'host' -and $parts[3] -eq 'pvsaccelerator_space_utilization') {
                $u = [double]$point.values[$k]
                # NaN: a gap in the series, not a real sample - never let it stick.
                if ([double]::IsNaN($u)) { continue }
                if (-not $peak.ContainsKey($parts[2]) -or $u -gt $peak[$parts[2]]) { $peak[$parts[2]] = $u }
            }
        }
    }
    foreach ($xenHost in Get-XenHost) {
        if ($peak.ContainsKey($xenHost.uuid)) {
            Write-Host ("  {0}: peak PVS cache utilisation {1:N0}%" -f $xenHost.name_label, $peak[$xenHost.uuid])
        }
    }
    Write-Host "OK: rrd-metrics"
    $session | Disconnect-XenServer
}
