function Invoke-ConfigureConsoleAccess {
    <#
    .SYNOPSIS
        Configure console access.
    .DESCRIPTION
        Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles
        and for VM consoles, one session at a time, and refusing plain HTTP. Restore every value it
        changed afterwards.
    .EXAMPLE
        Invoke-ConfigureConsoleAccess -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    $xenHost = Get-XenHost -Ref $pool.master.opaque_ref

    # NB: pool.https_only and pool.console_idle_timeout are SET below but never read back AT THE POOL
    # LEVEL. SDK 26.14 generates a setter and no getter for either there, because both are really
    # fan-outs that call the equivalent Set-XenHost on every host rather than pool fields of their own.
    # host.https_only and host.console_idle_timeout ARE ordinary readable fields, so this host's values
    # are read back through them instead, to show the effect and to know what to restore.
    $beforeVmConsoleIdleTimeout = $pool.vm_console_idle_timeout
    $beforeLimitConsoleSessions = $pool.limit_console_sessions
    $beforeHostConsoleIdleTimeout = $xenHost.console_idle_timeout
    $beforeHostHttpsOnly = $xenHost.https_only
    Write-Host ("  {0,-26} {1}s" -f "VM console idle timeout", $beforeVmConsoleIdleTimeout)
    Write-Host ("  {0,-26} {1}" -f "limit console sessions", $beforeLimitConsoleSessions)
    Write-Host ("  {0,-26} {1}s" -f "host console idle timeout", $beforeHostConsoleIdleTimeout)
    Write-Host ("  {0,-26} {1}" -f "host https only", $beforeHostHttpsOnly)

    # Ten minutes of inactivity, one console session at a time, and no plain HTTP.
    $pool | Set-XenPool -ConsoleIdleTimeout 600
    $pool | Set-XenPool -VmConsoleIdleTimeout 600
    $pool | Set-XenPool -LimitConsoleSessions $true
    $xenHost | Set-XenHost -ConsoleIdleTimeout 300
    $pool | Set-XenPool -HttpsOnly $true

    Write-Host "after tightening:"
    Write-Host ("  {0,-26} {1}s" -f "VM console idle timeout", (Get-XenPool -Ref $pool.opaque_ref).vm_console_idle_timeout)
    Write-Host ("  {0,-26} {1}" -f "limit console sessions", (Get-XenPool -Ref $pool.opaque_ref).limit_console_sessions)
    Write-Host ("  {0,-26} {1}s" -f "host console idle timeout", (Get-XenHost -Ref $xenHost.opaque_ref).console_idle_timeout)
    Write-Host ("  {0,-26} {1}" -f "host https only", (Get-XenHost -Ref $xenHost.opaque_ref).https_only)

    $pool | Set-XenPool -HttpsOnly $beforeHostHttpsOnly
    $pool | Set-XenPool -ConsoleIdleTimeout $beforeHostConsoleIdleTimeout
    $pool | Set-XenPool -VmConsoleIdleTimeout $beforeVmConsoleIdleTimeout
    $pool | Set-XenPool -LimitConsoleSessions $beforeLimitConsoleSessions
    $xenHost | Set-XenHost -ConsoleIdleTimeout $beforeHostConsoleIdleTimeout
    Write-Host "  restored"
    Write-Host "OK: configure-console-access"
    $session | Disconnect-XenServer
}
