function Invoke-ConfigureConsoleAccess {
    <#
    .SYNOPSIS
        Configure console access.
    .DESCRIPTION
        Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles
        and for VM consoles, one session at a time, and refusing plain HTTP.
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

    # NB: pool.https_only and pool.console_idle_timeout are SET below but never read back. SDK 26.14
    # generates a setter and no getter for both (unlike host.console_idle_timeout, which has both), so
    # they cannot be read through the typed bindings at all - and a sample that reached past its own
    # binding to show a value would be teaching a workaround rather than the API.
    Write-Host ("  {0,-26} {1}s" -f "VM console idle timeout", $pool.vm_console_idle_timeout)
    Write-Host ("  {0,-26} {1}" -f "limit console sessions", $pool.limit_console_sessions)
    Write-Host ("  {0,-26} {1}s" -f "host console idle timeout", $xenHost.console_idle_timeout)

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

    $pool | Set-XenPool -HttpsOnly $false
    $pool | Set-XenPool -ConsoleIdleTimeout 0
    $pool | Set-XenPool -VmConsoleIdleTimeout 0
    $pool | Set-XenPool -LimitConsoleSessions $false
    $xenHost | Set-XenHost -ConsoleIdleTimeout 0
    Write-Host "  restored"
    Write-Host "OK: configure-console-access"
    $session | Disconnect-XenServer
}
