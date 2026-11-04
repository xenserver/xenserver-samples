<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure console access

Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles and for VM consoles, one session at a time, and refusing plain HTTP.

Workflow `configure-console-access`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/ConfigureConsoleAccess.cs`](../../csharp/HostsAndPools/ConfigureConsoleAccess.cs)

```csharp
/// <summary>
/// Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles and
/// for VM consoles, one session at a time, and refusing plain HTTP.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureConsoleAccess("https://xenserver", "root", password);
/// </code>
/// </example>
/// <remarks>
/// <para>
/// Tighten how consoles and management traffic may be used. Idle console sessions are set at two levels —
/// the pool's own management consoles and the VM consoles it serves — and a host can override the pool's.
/// Requiring HTTPS refuses plain HTTP to the management interface altogether.
/// </para>
/// <para>
/// NOTE: SDK 26.14's C# binding has Pool.set_console_idle_timeout and Pool.set_https_only but no matching
/// GETTERS (unlike host.console_idle_timeout, which has both) — so the pool's own management-console
/// timeout and its HTTPS-only flag can be set here but not read back through this binding. Those two read
/// lines are therefore omitted rather than worked around.
/// </para>
/// </remarks>
public static void ConfigureConsoleAccess(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0].opaque_ref;
    var host = Pool.get_master(session, pool).opaque_ref;

    Console.WriteLine($"  {"VM console idle timeout",-26} {Pool.get_vm_console_idle_timeout(session, pool)}s");
    Console.WriteLine($"  {"limit console sessions",-26} {Pool.get_limit_console_sessions(session, pool)}");
    Console.WriteLine($"  {"host console idle timeout",-26} {Host.get_console_idle_timeout(session, host)}s");

    // Ten minutes of inactivity, one console session at a time, and no plain HTTP.
    Pool.set_console_idle_timeout(session, pool, 600);
    Pool.set_vm_console_idle_timeout(session, pool, 600);
    Pool.set_limit_console_sessions(session, pool, true);
    Host.set_console_idle_timeout(session, host, 300);
    Pool.set_https_only(session, pool, true);

    Console.WriteLine("after tightening:");
    Console.WriteLine($"  {"VM console idle timeout",-26} {Pool.get_vm_console_idle_timeout(session, pool)}s");
    Console.WriteLine($"  {"limit console sessions",-26} {Pool.get_limit_console_sessions(session, pool)}");
    Console.WriteLine($"  {"host console idle timeout",-26} {Host.get_console_idle_timeout(session, host)}s");

    Pool.set_https_only(session, pool, false);
    Pool.set_console_idle_timeout(session, pool, 0);
    Pool.set_vm_console_idle_timeout(session, pool, 0);
    Pool.set_limit_console_sessions(session, pool, false);
    Host.set_console_idle_timeout(session, host, 0);
    Console.WriteLine("  restored");
    Console.WriteLine("OK: configure-console-access");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     False
  host console idle timeout  0s
after tightening:
  VM console idle timeout    600s
  limit console sessions     True
  host console idle timeout  300s
  restored
OK: configure-console-access
```

</details>

## Python

Source: [`python/hosts_and_pools/configure_console_access.py`](../../python/hosts_and_pools/configure_console_access.py)

```python
"""Configure console access.

Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles
and for VM consoles, one session at a time, and refusing plain HTTP.

Run it::

    configure_console_access("https://xenserver", "root", password)
"""

from connection import connect


def configure_console_access(url, username, password):
    """Tighten how consoles and management traffic may be used.

    Idle console sessions are set at two levels -- the pool's own management consoles and the
    VM consoles it serves -- and a host can override the pool's. Requiring HTTPS refuses plain
    HTTP to the management interface altogether."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]
    host = x.pool.get_master(pool)

    # NB: pool.https_only and pool.console_idle_timeout are SET below but never read back. SDK 26.14
    # generates a setter and no getter for both (unlike host.console_idle_timeout, which has both), so
    # they cannot be read through the typed bindings at all — and a sample that reached past its own
    # binding to show a value would be teaching a workaround rather than the API.
    print("  %-26s %ss" % ("VM console idle timeout", x.pool.get_vm_console_idle_timeout(pool)))
    print("  %-26s %s" % ("limit console sessions", x.pool.get_limit_console_sessions(pool)))
    print("  %-26s %ss" % ("host console idle timeout", x.host.get_console_idle_timeout(host)))

    # Ten minutes of inactivity, one console session at a time, and no plain HTTP.
    x.pool.set_console_idle_timeout(pool, "600")
    x.pool.set_vm_console_idle_timeout(pool, "600")
    x.pool.set_limit_console_sessions(pool, True)
    x.host.set_console_idle_timeout(host, "300")
    x.pool.set_https_only(pool, True)

    print("after tightening:")
    print("  %-26s %ss" % ("VM console idle timeout", x.pool.get_vm_console_idle_timeout(pool)))
    print("  %-26s %s" % ("limit console sessions", x.pool.get_limit_console_sessions(pool)))
    print("  %-26s %ss" % ("host console idle timeout", x.host.get_console_idle_timeout(host)))

    x.pool.set_https_only(pool, False)
    x.pool.set_console_idle_timeout(pool, "0")
    x.pool.set_vm_console_idle_timeout(pool, "0")
    x.pool.set_limit_console_sessions(pool, False)
    x.host.set_console_idle_timeout(host, "0")
    print("  restored")
    print("OK: configure-console-access")
    session.logout()
```

<details><summary>Sample output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     False
  host console idle timeout  0s
after tightening:
  VM console idle timeout    600s
  limit console sessions     True
  host console idle timeout  300s
  restored
OK: configure-console-access
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureConsoleAccess.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureConsoleAccess.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureConsoleAccess {
    private ConfigureConsoleAccess() {
    }

    /**
     * Configure console access.
     *
     * <p>Tighten how consoles and management traffic may be used: idle timeouts for the pool's own
     * consoles and for VM consoles, one session at a time, and refusing plain HTTP.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureConsoleAccess.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Idle console sessions are set at two levels - the pool's own management consoles and the
            // VM consoles it serves - and a host can override the pool's. Requiring HTTPS refuses plain
            // HTTP to the management interface altogether.
            Pool pool = Pool.getAll(conn).iterator().next();
            Host host = pool.getMaster(conn);

            // NB: pool.https_only and pool.console_idle_timeout are SET below but never read back. SDK
            // 26.14 generates a setter and no getter for both (unlike host.console_idle_timeout, which
            // has both), so they cannot be read through the typed bindings at all - and a sample that
            // reached past its own binding to show a value would be teaching a workaround rather than
            // the API.
            System.out.printf("  %-26s %ss%n", "VM console idle timeout", pool.getVmConsoleIdleTimeout(conn));
            System.out.printf("  %-26s %s%n", "limit console sessions", pool.getLimitConsoleSessions(conn));
            System.out.printf("  %-26s %ss%n", "host console idle timeout", host.getConsoleIdleTimeout(conn));

            // Ten minutes of inactivity, one console session at a time, and no plain HTTP.
            pool.setConsoleIdleTimeout(conn, 600L);
            pool.setVmConsoleIdleTimeout(conn, 600L);
            pool.setLimitConsoleSessions(conn, true);
            host.setConsoleIdleTimeout(conn, 300L);
            pool.setHttpsOnly(conn, true);

            System.out.println("after tightening:");
            System.out.printf("  %-26s %ss%n", "VM console idle timeout", pool.getVmConsoleIdleTimeout(conn));
            System.out.printf("  %-26s %s%n", "limit console sessions", pool.getLimitConsoleSessions(conn));
            System.out.printf("  %-26s %ss%n", "host console idle timeout", host.getConsoleIdleTimeout(conn));

            pool.setHttpsOnly(conn, false);
            pool.setConsoleIdleTimeout(conn, 0L);
            pool.setVmConsoleIdleTimeout(conn, 0L);
            pool.setLimitConsoleSessions(conn, false);
            host.setConsoleIdleTimeout(conn, 0L);
            System.out.println("  restored");
            System.out.println("OK: configure-console-access");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Sample output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     false
  host console idle timeout  0s
after tightening:
  VM console idle timeout    600s
  limit console sessions     true
  host console idle timeout  300s
  restored
OK: configure-console-access
```

</details>

## Go

Source: [`go/configure_console_access.go`](../../go/configure_console_access.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// configureConsoleAccess - Configure console access.
//
// Tighten how consoles and management traffic may be used: idle timeouts for the pool's own
// consoles and for VM consoles, one session at a time, and refusing plain HTTP.
//
// Idle console sessions are set at two levels - the pool's own management consoles and the VM
// consoles it serves - and a host can override the pool's. Requiring HTTPS refuses plain HTTP to the
// management interface altogether.
//
// Run it:
//
//	configureConsoleAccess("https://xenserver", "root", password)
func configureConsoleAccess(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	host, err := xenapi.Pool.GetMaster(session, pool)
	check(err)

	// NB: pool.https_only and pool.console_idle_timeout are SET below but never read back. SDK 26.14
	// generates a setter and no getter for both (unlike host.console_idle_timeout, which has both), so
	// they cannot be read through the typed bindings at all - and a sample that reached past its own
	// binding to show a value would be teaching a workaround rather than the API.
	vmConsoleTimeout, err := xenapi.Pool.GetVMConsoleIdleTimeout(session, pool)
	check(err)
	limitSessions, err := xenapi.Pool.GetLimitConsoleSessions(session, pool)
	check(err)
	hostTimeout, err := xenapi.Host.GetConsoleIdleTimeout(session, host)
	check(err)
	fmt.Printf("  %-26s %ds\n", "VM console idle timeout", vmConsoleTimeout)
	fmt.Printf("  %-26s %t\n", "limit console sessions", limitSessions)
	fmt.Printf("  %-26s %ds\n", "host console idle timeout", hostTimeout)

	// Ten minutes of inactivity, one console session at a time, and no plain HTTP.
	check(xenapi.Pool.SetConsoleIdleTimeout(session, pool, 600))
	check(xenapi.Pool.SetVMConsoleIdleTimeout(session, pool, 600))
	check(xenapi.Pool.SetLimitConsoleSessions(session, pool, true))
	check(xenapi.Host.SetConsoleIdleTimeout(session, host, 300))
	check(xenapi.Pool.SetHTTPSOnly(session, pool, true))

	fmt.Println("after tightening:")
	vmConsoleTimeout, _ = xenapi.Pool.GetVMConsoleIdleTimeout(session, pool)
	limitSessions, _ = xenapi.Pool.GetLimitConsoleSessions(session, pool)
	hostTimeout, _ = xenapi.Host.GetConsoleIdleTimeout(session, host)
	fmt.Printf("  %-26s %ds\n", "VM console idle timeout", vmConsoleTimeout)
	fmt.Printf("  %-26s %t\n", "limit console sessions", limitSessions)
	fmt.Printf("  %-26s %ds\n", "host console idle timeout", hostTimeout)

	check(xenapi.Pool.SetHTTPSOnly(session, pool, false))
	check(xenapi.Pool.SetConsoleIdleTimeout(session, pool, 0))
	check(xenapi.Pool.SetVMConsoleIdleTimeout(session, pool, 0))
	check(xenapi.Pool.SetLimitConsoleSessions(session, pool, false))
	check(xenapi.Host.SetConsoleIdleTimeout(session, host, 0))
	fmt.Println("  restored")
	fmt.Println("OK: configure-console-access")
}
```

<details><summary>Sample output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     false
  host console idle timeout  0s
after tightening:
  VM console idle timeout    600s
  limit console sessions     true
  host console idle timeout  300s
  restored
OK: configure-console-access
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ConfigureConsoleAccess.ps1`](../../powershell/HostsAndPools/Invoke-ConfigureConsoleAccess.ps1)

```powershell
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
```

<details><summary>Sample output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     False
  host console idle timeout  0s
after tightening:
  VM console idle timeout    600s
  limit console sessions     True
  host console idle timeout  300s
  restored
OK: configure-console-access
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/configure-console-access.sh`](../../cli/hosts-and-pools/configure-console-access.sh)

```bash
# Configure console access.
#
# Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles and for
# VM consoles, one session at a time, and refusing plain HTTP.
#
# Run it:
#   ./workflows.sh configure-console-access https://xenserver root "$password"

configure_console_access() {
    # NOT `host`: that is the script-level variable the xe() wrapper passes to -s.
    pool=$(first_csv "$(xe pool-list --minimal)")
    host_uuid=$(xe pool-param-get uuid=$pool param-name=master)

    # NB: https-only and the pool console-idle-timeout are set but never read back. The generated SDK
    # bindings have a setter and no getter for both, so the other languages cannot show them - and these
    # samples are meant to read the same across all seven.
    printf '  %-26s %ss\n' "VM console idle timeout" "$(xe pool-param-get uuid=$pool param-name=vm-console-idle-timeout)"
    printf '  %-26s %s\n' "limit console sessions" "$(xe pool-param-get uuid=$pool param-name=limit-console-sessions)"
    printf '  %-26s %ss\n' "host console idle timeout" "$(xe host-param-get uuid=$host_uuid param-name=console-idle-timeout)"

    # Ten minutes of inactivity, one console session at a time, and no plain HTTP.
    xe pool-param-set uuid=$pool console-idle-timeout=600
    xe pool-param-set uuid=$pool vm-console-idle-timeout=600
    xe pool-param-set uuid=$pool limit-console-sessions=true
    xe host-param-set uuid=$host_uuid console-idle-timeout=300
    xe pool-param-set uuid=$pool https-only=true

    echo "after tightening:"
    printf '  %-26s %ss\n' "VM console idle timeout" "$(xe pool-param-get uuid=$pool param-name=vm-console-idle-timeout)"
    printf '  %-26s %s\n' "limit console sessions" "$(xe pool-param-get uuid=$pool param-name=limit-console-sessions)"
    printf '  %-26s %ss\n' "host console idle timeout" "$(xe host-param-get uuid=$host_uuid param-name=console-idle-timeout)"

    xe pool-param-set uuid=$pool https-only=false
    xe pool-param-set uuid=$pool console-idle-timeout=0
    xe pool-param-set uuid=$pool vm-console-idle-timeout=0
    xe pool-param-set uuid=$pool limit-console-sessions=false
    xe host-param-set uuid=$host_uuid console-idle-timeout=0
    echo "  restored"
    echo "OK: configure-console-access"
}
```

<details><summary>Sample output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     false
  host console idle timeout  0s
after tightening:
  VM console idle timeout    600s
  limit console sessions     true
  host console idle timeout  300s
  restored
OK: configure-console-access
```

</details>
