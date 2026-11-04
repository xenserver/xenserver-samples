function Invoke-ConfigureNrpe {
    <#
    .SYNOPSIS
        Configure NRPE monitoring.
    .DESCRIPTION
        Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read
        its status and configuration, enable it and permit a monitoring host, then read it back.
    .EXAMPLE
        Invoke-ConfigureNrpe -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    # host.call_plugin is per-host - there is no pool-wide fan-out for plugin calls the way there is for
    # pool.enable_ssh - so configure every host in the pool, and restore each one to disabled again
    # afterwards.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    foreach ($xenHost in Get-XenHost) {
        function Invoke-Nrpe([string]$Fn, [hashtable]$PluginArgs = @{}) {
            $xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin nrpe -Fn $Fn -Args $PluginArgs -PassThru
        }
        Write-Host "$($xenHost.name_label): NRPE status before: $((Invoke-Nrpe 'status').Trim())"
        Invoke-Nrpe 'enable' | Out-Null
        Invoke-Nrpe 'set-config' @{ allowed_hosts = "127.0.0.1,::1,192.0.2.60"; debug = "0"; ssl_logging = "0x00" } | Out-Null
        Invoke-Nrpe 'restart' | Out-Null
        Write-Host "  status after:  $((Invoke-Nrpe 'status').Trim())"
        foreach ($line in ((Invoke-Nrpe 'get-config') -split "`n")) {
            if ($line.StartsWith('allowed_hosts:')) {
                Write-Host "  allowed hosts: $($line.Split(':', 2)[1].Trim())"
            }
        }
        Invoke-Nrpe 'disable' | Out-Null   # restore: leave it as we found it
    }
    Write-Host "OK: configure-nrpe"
    $session | Disconnect-XenServer
}
