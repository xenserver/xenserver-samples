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
    # pool.enable_ssh - so configure every host in the pool, and restore each one to exactly the state
    # (enabled or not, and its configuration) it was found in afterwards.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    foreach ($xenHost in Get-XenHost) {
        function Invoke-Nrpe([string]$Fn, [hashtable]$PluginArgs = @{}) {
            $xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin nrpe -Fn $Fn -Args $PluginArgs -PassThru
        }

        # Capture what we're about to change, to put back afterwards.
        $statusBefore = (Invoke-Nrpe 'status').Trim()
        $wasEnabled = ($statusBefore -split '\s+')[-1] -eq 'enabled'
        $beforeConfig = @{}
        foreach ($line in ((Invoke-Nrpe 'get-config') -split "`n")) {
            $parts = $line.Split(':', 2)
            if ($parts.Length -eq 2 -and @('allowed_hosts', 'debug', 'ssl_logging') -contains $parts[0].Trim()) {
                $beforeConfig[$parts[0].Trim()] = $parts[1].Trim()
            }
        }

        Write-Host "$($xenHost.name_label): NRPE status before: $statusBefore"
        Invoke-Nrpe 'enable' | Out-Null
        Invoke-Nrpe 'set-config' @{ allowed_hosts = "127.0.0.1,::1,192.0.2.60"; debug = "0"; ssl_logging = "0x00" } | Out-Null
        Invoke-Nrpe 'restart' | Out-Null
        Write-Host "  status after:  $((Invoke-Nrpe 'status').Trim())"
        foreach ($line in ((Invoke-Nrpe 'get-config') -split "`n")) {
            if ($line.StartsWith('allowed_hosts:')) {
                Write-Host "  allowed hosts: $($line.Split(':', 2)[1].Trim())"
            }
        }

        # Restore exactly what was found, rather than always disabling: a host that already had NRPE
        # enabled and configured should not be left changed.
        Invoke-Nrpe 'set-config' $beforeConfig | Out-Null
        if ($wasEnabled) {
            Invoke-Nrpe 'restart' | Out-Null
        } else {
            Invoke-Nrpe 'disable' | Out-Null
        }
    }
    Write-Host "OK: configure-nrpe"
    $session | Disconnect-XenServer
}
