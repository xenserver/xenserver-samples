<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Send logs to a remote syslog server

Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the setting is recorded but nothing changes.

Workflow `configure-syslog`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/ConfigureSyslog.cs`](../../csharp/HostsAndPools/ConfigureSyslog.cs)

```csharp
/// <summary>
/// Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the setting
/// is recorded but nothing changes.
/// </summary>
public static void ConfigureSyslog(string url, string user, string password,
    string syslogServer = "192.0.2.50")
{
    var session = Connect(url, user, password);
    var host = Pool.get_master(session, Pool.get_all(session)[0].opaque_ref).opaque_ref;

    Console.WriteLine($"{Host.get_name_label(session, host)} logging: {LoggingLabel(session, host)}");

    // Two steps, and the second is the one that is easy to miss: setting the destination only
    // records it, and the host keeps logging locally until the syslog daemon is reconfigured to
    // pick the setting up.
    Host.remove_from_logging(session, host, "syslog_destination");
    Host.add_to_logging(session, host, "syslog_destination", syslogServer);
    Host.syslog_reconfigure(session, host);
    Console.WriteLine($"  now logging to: {Host.get_logging(session, host)["syslog_destination"]}");

    Host.remove_from_logging(session, host, "syslog_destination");
    Host.syslog_reconfigure(session, host);
    Console.WriteLine($"  restored: {LoggingLabel(session, host)}");
    Console.WriteLine("OK: configure-syslog");
    session.logout();
}

/// <summary>The host's logging config, or "(local only)" when nothing is configured.</summary>
private static string LoggingLabel(Session session, string host)
{
    var logging = Host.get_logging(session, host);
    return logging.Count == 0 ? "(local only)" : string.Join(", ", logging.Select(kv => $"{kv.Key}={kv.Value}"));
}
```

<details><summary>Sample output</summary>

```text
sdk-host1 logging: (local only)
  now logging to: 192.0.2.50
  restored: (local only)
OK: configure-syslog
```

</details>

## Python

Source: [`python/hosts_and_pools/configure_syslog.py`](../../python/hosts_and_pools/configure_syslog.py)

```python
"""Send logs to a remote syslog server.

Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the
setting is recorded but nothing changes.

Run it::

    configure_syslog("https://xenserver", "root", password)
"""

from connection import connect


def configure_syslog(url, username, password, syslog_server="192.0.2.50"):
    """Send a host's logs to a remote syslog server.

    Two steps, and the second is the one that is easy to miss: setting the destination only
    records it, and the host keeps logging locally until the syslog daemon is reconfigured to
    pick the setting up."""
    session = connect(url, username, password)
    x = session.xenapi
    host = x.pool.get_master(x.pool.get_all()[0])

    print("%s logging: %s" % (x.host.get_name_label(host), x.host.get_logging(host) or "(local only)"))

    x.host.remove_from_logging(host, "syslog_destination")
    x.host.add_to_logging(host, "syslog_destination", syslog_server)
    x.host.syslog_reconfigure(host)
    print("  now logging to: %s" % x.host.get_logging(host)["syslog_destination"])

    x.host.remove_from_logging(host, "syslog_destination")
    x.host.syslog_reconfigure(host)
    print("  restored: %s" % (x.host.get_logging(host) or "(local only)"))
    print("OK: configure-syslog")
    session.logout()
```

<details><summary>Sample output</summary>

```text
sdk-host1 logging: (local only)
  now logging to: 192.0.2.50
  restored: (local only)
OK: configure-syslog
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureSyslog.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureSyslog.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureSyslog {
    private ConfigureSyslog() {
    }

    /**
     * Send logs to a remote syslog server.
     *
     * <p>Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the
     * setting is recorded but nothing changes.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureSyslog.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password, String syslogServer)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Two steps, and the second is the one that is easy to miss: setting the destination only
            // records it, and the host keeps logging locally until the syslog daemon is reconfigured to
            // pick the setting up.
            Host host = Pool.getAll(conn).iterator().next().getMaster(conn);

            Map<String, String> logging = host.getLogging(conn);
            System.out.println(host.getNameLabel(conn) + " logging: "
                    + (logging.isEmpty() ? "(local only)" : logging));

            host.removeFromLogging(conn, "syslog_destination");
            host.addToLogging(conn, "syslog_destination", syslogServer);
            host.syslogReconfigure(conn);
            System.out.println("  now logging to: " + host.getLogging(conn).get("syslog_destination"));

            host.removeFromLogging(conn, "syslog_destination");
            host.syslogReconfigure(conn);
            Map<String, String> after = host.getLogging(conn);
            System.out.println("  restored: " + (after.isEmpty() ? "(local only)" : after));
            System.out.println("OK: configure-syslog");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Sample output</summary>

```text
sdk-host1 logging: (local only)
  now logging to: 192.0.2.50
  restored: (local only)
OK: configure-syslog
```

</details>

## Go

Source: [`go/configure_syslog.go`](../../go/configure_syslog.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// configureSyslog - Send logs to a remote syslog server.
//
// Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the
// setting is recorded but nothing changes.
//
// Two steps, and the second is the one that is easy to miss: setting the destination only records
// it, and the host keeps logging locally until the syslog daemon is reconfigured to pick the setting
// up.
func configureSyslog(url, user, password, syslogServer string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	hostName, err := xenapi.Host.GetNameLabel(session, host)
	check(err)

	logging, err := xenapi.Host.GetLogging(session, host)
	check(err)
	fmt.Printf("%s logging: %s\n", hostName, loggingOrLocal(logging))

	check(xenapi.Host.RemoveFromLogging(session, host, "syslog_destination"))
	check(xenapi.Host.AddToLogging(session, host, "syslog_destination", syslogServer))
	check(xenapi.Host.SyslogReconfigure(session, host))
	logging, _ = xenapi.Host.GetLogging(session, host)
	fmt.Printf("  now logging to: %s\n", logging["syslog_destination"])

	check(xenapi.Host.RemoveFromLogging(session, host, "syslog_destination"))
	check(xenapi.Host.SyslogReconfigure(session, host))
	logging, _ = xenapi.Host.GetLogging(session, host)
	fmt.Printf("  restored: %s\n", loggingOrLocal(logging))
	fmt.Println("OK: configure-syslog")
}

// loggingOrLocal renders a host's logging map, or "(local only)" once it is empty.
func loggingOrLocal(logging map[string]string) string {
	if len(logging) == 0 {
		return "(local only)"
	}
	return fmt.Sprintf("%v", logging)
}
```

<details><summary>Sample output</summary>

```text
sdk-host1 logging: (local only)
  now logging to: 192.0.2.50
  restored: (local only)
OK: configure-syslog
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ConfigureSyslog.ps1`](../../powershell/HostsAndPools/Invoke-ConfigureSyslog.ps1)

```powershell
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
    $xenHost = Get-XenHost -Ref (Get-XenPool | Select-Object -First 1).master.opaque_ref

    Write-Host "$($xenHost.name_label) logging: $(Format-Logging $xenHost.logging)"

    # Two steps, and the second is the one that is easy to miss: setting the destination only records
    # it, and the host keeps logging locally until the syslog daemon is reconfigured to pick the
    # setting up. Add-XenHost appends one logging entry as a KeyValuePair; Remove-XenHostProperty drops
    # it again by key.
    $xenHost | Remove-XenHostProperty -Logging "syslog_destination"
    $xenHost | Add-XenHost -Logging ([System.Collections.Generic.KeyValuePair[string, string]]::new("syslog_destination", $SyslogServer))
    $xenHost | Invoke-XenHost -XenAction SyslogReconfigure
    Write-Host "  now logging to: $((Get-XenHost -Ref $xenHost.opaque_ref).logging['syslog_destination'])"

    $xenHost | Remove-XenHostProperty -Logging "syslog_destination"
    $xenHost | Invoke-XenHost -XenAction SyslogReconfigure
    Write-Host "  restored: $(Format-Logging (Get-XenHost -Ref $xenHost.opaque_ref).logging)"
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
```

<details><summary>Sample output</summary>

```text
sdk-host1 logging: (local only)
  now logging to: 192.0.2.50
  restored: (local only)
OK: configure-syslog
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/configure-syslog.sh`](../../cli/hosts-and-pools/configure-syslog.sh)

```bash
# Send logs to a remote syslog server.
#
# Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the setting is
# recorded but nothing changes.
#
# Run it:
#   ./workflows.sh configure-syslog https://xenserver root "$password"

configure_syslog() {
    pool=$(first_csv "$(xe pool-list --minimal)")
    host_uuid=$(xe pool-param-get uuid=$pool param-name=master)
    syslog_server=192.0.2.50

    logging=$(xe host-param-get uuid=$host_uuid param-name=logging)
    echo "$(xe host-param-get uuid=$host_uuid param-name=name-label) logging: ${logging:-(local only)}"

    # Two steps, and the second is the one that is easy to miss: setting the destination only
    # records it, and the host keeps logging locally until the syslog daemon is reconfigured to
    # pick the setting up. (Removing a key that is not there is an error, hence the || true.)
    xe host-param-remove uuid=$host_uuid param-name=logging param-key=syslog_destination >/dev/null 2>&1 || true
    xe host-param-set uuid=$host_uuid logging:syslog_destination=$syslog_server
    xe host-syslog-reconfigure host-uuid=$host_uuid
    echo "  now logging to: $(xe host-param-get uuid=$host_uuid param-name=logging param-key=syslog_destination)"

    xe host-param-remove uuid=$host_uuid param-name=logging param-key=syslog_destination
    xe host-syslog-reconfigure host-uuid=$host_uuid
    logging=$(xe host-param-get uuid=$host_uuid param-name=logging)
    echo "  restored: ${logging:-(local only)}"
    echo "OK: configure-syslog"
}
```

<details><summary>Sample output</summary>

```text
sdk-host1 logging: (local only)
  now logging to: 192.0.2.50
  restored: (local only)
OK: configure-syslog
```

</details>
