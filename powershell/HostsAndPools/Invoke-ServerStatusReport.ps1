function Invoke-ServerStatusReport {
    <#
    .SYNOPSIS
        Collect a server status report.
    .DESCRIPTION
        Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the
        whole bundle, then download a smaller one covering only the sections you pick.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # Report on the coordinator. Each host answers for itself, so which one you ask decides whose logs
    # you get - support normally wants every host, one download each.
    $pool = Get-XenPool | Select-Object -First 1
    $xenHost = Get-XenHost -Ref $pool.master.opaque_ref
    Write-Host "Status report for $($xenHost.name_label)"

    # The host publishes a catalogue of the sections it can report on, each with a size estimate and
    # whether it may contain personal data, so a client can offer an informed choice rather than
    # hard-coding the list.
    # A read, so it is a property rather than an action: Invoke-XenHost's -XenAction set covers the
    # host's verbs, and this is not one of them.
    $catalogue = [xml](Get-XenHostProperty -XenHost $xenHost -XenProperty SystemStatusCapabilities)
    $keys = @()
    $defaults = @()
    foreach ($capability in $catalogue.'system-status-capabilities'.capability) {
        $keys += $capability.key
        if ($capability.'default-checked' -eq 'yes') { $defaults += $capability.key }
        Write-Host ("  {0,-22} max {1,9} bytes  default={2,-3} pii={3}" -f
            $capability.key, $capability.'max-size', $capability.'default-checked', $capability.pii)
    }

    # The download is an HTTP transfer alongside the API, so the session id travels in the query string.
    # Still pure PowerShell: Connect-Example has already trusted the server's certificate. Take the
    # sections the host marks default-checked: asking for every section can mean gigabytes (VM memory
    # dumps, every log) and a long wait while the host builds it.
    $whole = Get-StatusReportSize -Url $Url -Session $session -Entries $defaults
    Write-Host ("default sections ({0} of {1}): {2} bytes" -f $defaults.Count, $keys.Count, $whole)

    # Pick a real, small section from the host's own catalogue rather than assuming a name: the
    # catalogue is server-defined (xen-bugtool's own --capabilities output), not a fixed client list,
    # and "xenserver-config" isn't one of the real keys any host actually publishes.
    $subsetKey = $keys | Where-Object { $_ -in @("firstboot", "network-status") } | Select-Object -First 1
    if (-not $subsetKey) { $subsetKey = $keys[0] }
    $subset = Get-StatusReportSize -Url $Url -Session $session -Entries @($subsetKey)
    Write-Host ("{0} only:   {1} bytes" -f $subsetKey, $subset)
    if ($subset -ge $whole) {
        Write-Host "  ERROR: selecting fewer sections did not produce a smaller bundle"
    }

    Write-Host "OK: server-status-report"
    $session | Disconnect-XenServer
}

function Get-StatusReportSize {
    <#
    .SYNOPSIS
        Downloads the bundle for the given capability keys (a tar archive) to a temp file, streaming it - a
        report can be large - and returns its size.
    .DESCRIPTION
        This example then deletes it; you'd keep it.
    #>
    param([string]$Url, $Session, [string[]]$Entries)
    $path = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-status-$([guid]::NewGuid().Guid).tar"
    try {
        Invoke-WebRequest -UseBasicParsing -OutFile $path `
            -Uri ("$Url/system-status?session_id=$($Session.opaque_ref)&output=tar" +
                  "&entries=$($Entries -join ',')")
        (Get-Item $path).Length
    }
    finally {
        Remove-Item $path -ErrorAction SilentlyContinue
    }
}
