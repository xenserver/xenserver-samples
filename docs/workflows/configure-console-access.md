<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure console access

Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles and for VM consoles, one session at a time, and refusing plain HTTP.

Workflow `configure-console-access`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ConfigureConsoleAccess.ps1`](../../powershell/HostsAndPools/Invoke-ConfigureConsoleAccess.ps1)

```powershell
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
```

<details><summary>Example output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     False
  host console idle timeout  0s
  host https only            False
after tightening:
  VM console idle timeout    600s
  limit console sessions     True
  host console idle timeout  300s
  host https only            True
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
# VM consoles, one session at a time, and refusing plain HTTP. Restore every value it changed afterwards.
#
# Run it:
#   ./workflows.sh configure-console-access https://xenserver root "$password"

configure_console_access() {
    # NOT `host`: that is the script-level variable the xe() wrapper passes to -s.
    pool=$(first_csv "$(xe pool-list --minimal)")
    host_uuid=$(xe pool-param-get uuid=$pool param-name=master)

    # NB: pool https-only and pool console-idle-timeout are set below but never read back AT THE POOL
    # LEVEL. The generated SDK bindings have a setter and no getter for either there, because both are
    # really fan-outs that set the equivalent host field on every host rather than pool fields of their
    # own. host https-only and host console-idle-timeout ARE ordinary readable fields, so read this host's
    # values back instead, to show the effect and to know what to restore.
    before_vm_console_idle_timeout=$(xe pool-param-get uuid=$pool param-name=vm-console-idle-timeout)
    before_limit_console_sessions=$(xe pool-param-get uuid=$pool param-name=limit-console-sessions)
    before_host_console_idle_timeout=$(xe host-param-get uuid=$host_uuid param-name=console-idle-timeout)
    before_host_https_only=$(xe host-param-get uuid=$host_uuid param-name=https-only)
    printf '  %-26s %ss\n' "VM console idle timeout" "$before_vm_console_idle_timeout"
    printf '  %-26s %s\n' "limit console sessions" "$before_limit_console_sessions"
    printf '  %-26s %ss\n' "host console idle timeout" "$before_host_console_idle_timeout"
    printf '  %-26s %s\n' "host https only" "$before_host_https_only"

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
    printf '  %-26s %s\n' "host https only" "$(xe host-param-get uuid=$host_uuid param-name=https-only)"

    xe pool-param-set uuid=$pool https-only=$before_host_https_only
    xe pool-param-set uuid=$pool console-idle-timeout=$before_host_console_idle_timeout
    xe pool-param-set uuid=$pool vm-console-idle-timeout=$before_vm_console_idle_timeout
    xe pool-param-set uuid=$pool limit-console-sessions=$before_limit_console_sessions
    xe host-param-set uuid=$host_uuid console-idle-timeout=$before_host_console_idle_timeout
    echo "  restored"
    echo "OK: configure-console-access"
}
```

<details><summary>Example output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     false
  host console idle timeout  0s
  host https only            false
after tightening:
  VM console idle timeout    600s
  limit console sessions     true
  host console idle timeout  300s
  host https only            true
  restored
OK: configure-console-access
```

</details>

## Python

Source: [`python/hosts_and_pools/configure_console_access.py`](../../python/hosts_and_pools/configure_console_access.py)

```python
"""Configure console access.

Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles
and for VM consoles, one session at a time, and refusing plain HTTP. Restore every value it changed
afterwards.

Run it::

    configure_console_access("https://xenserver", "root", password)
"""

from connection import connect


def configure_console_access(url, username, password):
    """Tighten how consoles and management traffic may be used, then put back whatever was there
    before.

    Idle console sessions are set at two levels -- the pool's own management consoles and the
    VM consoles it serves -- and a host can override the pool's. Requiring HTTPS refuses plain
    HTTP to the management interface altogether."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]
    host = x.pool.get_master(pool)

    # NB: pool.https_only and pool.console_idle_timeout are SET below but never read back AT THE POOL
    # LEVEL. SDK 26.14 generates a setter and no getter for either there, because both are really
    # fan-outs that call the equivalent Host.set_* on every host rather than pool fields of their own.
    # host.https_only and host.console_idle_timeout ARE ordinary readable fields, so read this host's
    # values back through them instead, to show the effect and to know what to restore.
    before_vm_console_idle_timeout = x.pool.get_vm_console_idle_timeout(pool)
    before_limit_console_sessions = x.pool.get_limit_console_sessions(pool)
    before_host_console_idle_timeout = x.host.get_console_idle_timeout(host)
    before_host_https_only = x.host.get_https_only(host)
    print("  %-26s %ss" % ("VM console idle timeout", before_vm_console_idle_timeout))
    print("  %-26s %s" % ("limit console sessions", before_limit_console_sessions))
    print("  %-26s %ss" % ("host console idle timeout", before_host_console_idle_timeout))
    print("  %-26s %s" % ("host https only", before_host_https_only))

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
    print("  %-26s %s" % ("host https only", x.host.get_https_only(host)))

    x.pool.set_https_only(pool, before_host_https_only)
    x.pool.set_console_idle_timeout(pool, str(before_host_console_idle_timeout))
    x.pool.set_vm_console_idle_timeout(pool, str(before_vm_console_idle_timeout))
    x.pool.set_limit_console_sessions(pool, before_limit_console_sessions)
    x.host.set_console_idle_timeout(host, str(before_host_console_idle_timeout))
    print("  restored")
    print("OK: configure-console-access")
    session.logout()
```

<details><summary>Example output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     False
  host console idle timeout  0s
  host https only            False
after tightening:
  VM console idle timeout    600s
  limit console sessions     True
  host console idle timeout  300s
  host https only            True
  restored
OK: configure-console-access
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/ConfigureConsoleAccess.cs`](../../csharp/HostsAndPools/ConfigureConsoleAccess.cs)

```csharp
/// <summary>
/// Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles and
/// for VM consoles, one session at a time, and refusing plain HTTP. Restore every value it changed
/// afterwards.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureConsoleAccess("https://xenserver", "root", password);
/// </code>
/// </example>
/// <remarks>
/// <para>
/// Tighten how consoles and management traffic may be used, then put back whatever was there before.
/// Idle console sessions are set at two levels — the pool's own management consoles and the VM consoles
/// it serves — and a host can override the pool's. Requiring HTTPS refuses plain HTTP to the management
/// interface altogether.
/// </para>
/// <para>
/// NOTE: Pool.set_console_idle_timeout and Pool.set_https_only are set below but never read back AT THE
/// POOL LEVEL. SDK 26.14 generates a setter and no getter for either there, because both are really
/// fan-outs that call the equivalent Host.set_* on every host rather than pool fields of their own.
/// Host.https_only and Host.console_idle_timeout ARE ordinary readable fields, so this host's values are
/// read back through them instead, to show the effect and to know what to restore.
/// </para>
/// </remarks>
public static void ConfigureConsoleAccess(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0].opaque_ref;
    var host = Pool.get_master(session, pool).opaque_ref;

    var beforeVmConsoleIdleTimeout = Pool.get_vm_console_idle_timeout(session, pool);
    var beforeLimitConsoleSessions = Pool.get_limit_console_sessions(session, pool);
    var beforeHostConsoleIdleTimeout = Host.get_console_idle_timeout(session, host);
    var beforeHostHttpsOnly = Host.get_https_only(session, host);
    Console.WriteLine($"  {"VM console idle timeout",-26} {beforeVmConsoleIdleTimeout}s");
    Console.WriteLine($"  {"limit console sessions",-26} {beforeLimitConsoleSessions}");
    Console.WriteLine($"  {"host console idle timeout",-26} {beforeHostConsoleIdleTimeout}s");
    Console.WriteLine($"  {"host https only",-26} {beforeHostHttpsOnly}");

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
    Console.WriteLine($"  {"host https only",-26} {Host.get_https_only(session, host)}");

    Pool.set_https_only(session, pool, beforeHostHttpsOnly);
    Pool.set_console_idle_timeout(session, pool, beforeHostConsoleIdleTimeout);
    Pool.set_vm_console_idle_timeout(session, pool, beforeVmConsoleIdleTimeout);
    Pool.set_limit_console_sessions(session, pool, beforeLimitConsoleSessions);
    Host.set_console_idle_timeout(session, host, beforeHostConsoleIdleTimeout);
    Console.WriteLine("  restored");
    Console.WriteLine("OK: configure-console-access");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     False
  host console idle timeout  0s
  host https only            False
after tightening:
  VM console idle timeout    600s
  limit console sessions     True
  host console idle timeout  300s
  host https only            True
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
// consoles and for VM consoles, one session at a time, and refusing plain HTTP. Restore every
// value it changed afterwards.
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

	// NB: pool.https_only and pool.console_idle_timeout are SET below but never read back AT THE POOL
	// LEVEL. SDK 26.14 generates a setter and no getter for either there, because both are really
	// fan-outs that call the equivalent Host.Set* on every host rather than pool fields of their own.
	// host.https_only and host.console_idle_timeout ARE ordinary readable fields, so read this host's
	// values back through them instead, to show the effect and to know what to restore.
	beforeVMConsoleTimeout, err := xenapi.Pool.GetVMConsoleIdleTimeout(session, pool)
	check(err)
	beforeLimitSessions, err := xenapi.Pool.GetLimitConsoleSessions(session, pool)
	check(err)
	beforeHostTimeout, err := xenapi.Host.GetConsoleIdleTimeout(session, host)
	check(err)
	beforeHostHTTPSOnly, err := xenapi.Host.GetHTTPSOnly(session, host)
	check(err)
	fmt.Printf("  %-26s %ds\n", "VM console idle timeout", beforeVMConsoleTimeout)
	fmt.Printf("  %-26s %t\n", "limit console sessions", beforeLimitSessions)
	fmt.Printf("  %-26s %ds\n", "host console idle timeout", beforeHostTimeout)
	fmt.Printf("  %-26s %t\n", "host https only", beforeHostHTTPSOnly)

	// Ten minutes of inactivity, one console session at a time, and no plain HTTP.
	check(xenapi.Pool.SetConsoleIdleTimeout(session, pool, 600))
	check(xenapi.Pool.SetVMConsoleIdleTimeout(session, pool, 600))
	check(xenapi.Pool.SetLimitConsoleSessions(session, pool, true))
	check(xenapi.Host.SetConsoleIdleTimeout(session, host, 300))
	check(xenapi.Pool.SetHTTPSOnly(session, pool, true))

	fmt.Println("after tightening:")
	vmConsoleTimeout, _ := xenapi.Pool.GetVMConsoleIdleTimeout(session, pool)
	limitSessions, _ := xenapi.Pool.GetLimitConsoleSessions(session, pool)
	hostTimeout, _ := xenapi.Host.GetConsoleIdleTimeout(session, host)
	hostHTTPSOnly, _ := xenapi.Host.GetHTTPSOnly(session, host)
	fmt.Printf("  %-26s %ds\n", "VM console idle timeout", vmConsoleTimeout)
	fmt.Printf("  %-26s %t\n", "limit console sessions", limitSessions)
	fmt.Printf("  %-26s %ds\n", "host console idle timeout", hostTimeout)
	fmt.Printf("  %-26s %t\n", "host https only", hostHTTPSOnly)

	check(xenapi.Pool.SetHTTPSOnly(session, pool, beforeHostHTTPSOnly))
	check(xenapi.Pool.SetConsoleIdleTimeout(session, pool, beforeHostTimeout))
	check(xenapi.Pool.SetVMConsoleIdleTimeout(session, pool, beforeVMConsoleTimeout))
	check(xenapi.Pool.SetLimitConsoleSessions(session, pool, beforeLimitSessions))
	check(xenapi.Host.SetConsoleIdleTimeout(session, host, beforeHostTimeout))
	fmt.Println("  restored")
	fmt.Println("OK: configure-console-access")
}
```

<details><summary>Example output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     false
  host console idle timeout  0s
  host https only            false
after tightening:
  VM console idle timeout    600s
  limit console sessions     true
  host console idle timeout  300s
  host https only            true
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
     * consoles and for VM consoles, one session at a time, and refusing plain HTTP. Restore every
     * value it changed afterwards.
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

            // NB: pool.https_only and pool.console_idle_timeout are SET below but never read back AT THE
            // POOL LEVEL. SDK 26.14 generates a setter and no getter for either there, because both are
            // really fan-outs that call the equivalent Host.set* on every host rather than pool fields of
            // their own. host.https_only and host.console_idle_timeout ARE ordinary readable fields, so
            // read this host's values back through them instead, to show the effect and to know what to
            // restore.
            long beforeVmConsoleIdleTimeout = pool.getVmConsoleIdleTimeout(conn);
            boolean beforeLimitConsoleSessions = pool.getLimitConsoleSessions(conn);
            long beforeHostConsoleIdleTimeout = host.getConsoleIdleTimeout(conn);
            boolean beforeHostHttpsOnly = host.getHttpsOnly(conn);
            System.out.printf("  %-26s %ss%n", "VM console idle timeout", beforeVmConsoleIdleTimeout);
            System.out.printf("  %-26s %s%n", "limit console sessions", beforeLimitConsoleSessions);
            System.out.printf("  %-26s %ss%n", "host console idle timeout", beforeHostConsoleIdleTimeout);
            System.out.printf("  %-26s %s%n", "host https only", beforeHostHttpsOnly);

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
            System.out.printf("  %-26s %s%n", "host https only", host.getHttpsOnly(conn));

            pool.setHttpsOnly(conn, beforeHostHttpsOnly);
            pool.setConsoleIdleTimeout(conn, beforeHostConsoleIdleTimeout);
            pool.setVmConsoleIdleTimeout(conn, beforeVmConsoleIdleTimeout);
            pool.setLimitConsoleSessions(conn, beforeLimitConsoleSessions);
            host.setConsoleIdleTimeout(conn, beforeHostConsoleIdleTimeout);
            System.out.println("  restored");
            System.out.println("OK: configure-console-access");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
  VM console idle timeout    0s
  limit console sessions     false
  host console idle timeout  0s
  host https only            false
after tightening:
  VM console idle timeout    600s
  limit console sessions     true
  host console idle timeout  300s
  host https only            true
  restored
OK: configure-console-access
```

</details>
