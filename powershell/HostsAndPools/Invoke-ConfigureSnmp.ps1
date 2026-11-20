function Invoke-ConfigureSnmp {
    <#
    .SYNOPSIS
        Configure SNMP monitoring.
    .DESCRIPTION
        Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with
        a community string and a trap destination, read it back, then put the original configuration back.
    .EXAMPLE
        Invoke-ConfigureSnmp -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$TrapDestination = "192.0.2.50"
    )
    # nmss is the list of real trap destinations SNMP notifications go to - an empty list never
    # configures where traps actually go, which is the whole point of "configure SNMP monitoring".
    # Plugin calls are per-host, so configure every host, and restore each one to what it had before,
    # rather than assuming it was disabled.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $config = @{
        common = @{ enabled = "yes"; debug_log = "no" }
        agent  = @{ v2c = "yes"; v3 = "no"; community = "sdk-community"; user_name = "";
                    authentication_password = ""; authentication_protocol = "";
                    privacy_password = ""; privacy_protocol = "" }
        # Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
        nmss   = @(@{ uuid = [guid]::NewGuid().ToString(); address = $TrapDestination; port = 162; v2c = "yes"; v3 = "no";
                      community = "sdk-community"; user_name = ""; authentication_password = "";
                      authentication_protocol = ""; privacy_password = ""; privacy_protocol = "" })
    }
    $configJson = [string]($config | ConvertTo-Json -Compress -Depth 5)
    foreach ($xenHost in Get-XenHost) {
        # Keep the host's own configuration so it can be put back, rather than left disabled.
        $before = (($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn get-config -Args @{} -PassThru) | ConvertFrom-Json).result
        # The plugin reports a refused config in its answer, not as an API error: check it.
        $answer = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn set-config `
            -Args @{ config = $configJson } -PassThru) | ConvertFrom-Json
        if ($answer.code -ne 0) { throw "set-config refused the configuration: $($answer.message)" }
        $status = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn status -Args @{} -PassThru) | ConvertFrom-Json
        $cfg = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn get-config -Args @{} -PassThru) | ConvertFrom-Json
        Write-Host "$($xenHost.name_label): SNMP enabled: $($status.result.enabled) / $($status.result.active)"
        $trapAddress = if (@($cfg.result.nmss).Count -gt 0) { $cfg.result.nmss[0].address } else { "(none)" }
        Write-Host "  community: $($cfg.result.agent.community), trap destination: $trapAddress"
        $beforeJson = [string]($before | ConvertTo-Json -Compress -Depth 5)
        $restore = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn set-config `
            -Args @{ config = $beforeJson } -PassThru) | ConvertFrom-Json
        if ($restore.code -ne 0) { throw "set-config refused to restore the configuration: $($restore.message)" }
    }
    Write-Host "OK: configure-snmp"
    $session | Disconnect-XenServer
}
