function Invoke-ConfigureSyslog {
    <#
    .SYNOPSIS
        Send logs to a remote syslog server.
    .DESCRIPTION
        Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the
        setting is recorded but nothing changes.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$SyslogServer = "192.0.2.50"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost -Ref (Get-XenPool | Select-Object -First 1).master

    Write-Host "$($xenHost.name_label) logging: $(Format-Logging $xenHost.logging)"

    # Two steps, and the second is the one that is easy to miss: setting the destination only records
    # it, and the host keeps logging locally until the syslog daemon is reconfigured to pick the
    # setting up. Add-XenHost appends one logging entry as a KeyValuePair; Remove-XenHostProperty drops
    # it again by key.
    $xenHost | Remove-XenHostProperty -Logging "syslog_destination"
    $xenHost | Add-XenHost -Logging ([System.Collections.Generic.KeyValuePair[string, string]]::new("syslog_destination", $SyslogServer))
    $xenHost | Invoke-XenHost -XenAction SyslogReconfigure
    Write-Host "  now logging to: $((Get-XenHost -Ref $xenHost).logging['syslog_destination'])"

    $xenHost | Remove-XenHostProperty -Logging "syslog_destination"
    $xenHost | Invoke-XenHost -XenAction SyslogReconfigure
    Write-Host "  restored: $(Format-Logging (Get-XenHost -Ref $xenHost).logging)"
    Write-Host "OK: configure-syslog"
    $session | Disconnect-XenServer
}

function Format-Logging {
    <#
    .SYNOPSIS
        The host's logging map, tolerating the empty map a host with no remote destination has.
    #>
    param($Logging)
    if (-not $Logging -or $Logging.Count -eq 0) { return "(local only)" }
    ($Logging.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
}
