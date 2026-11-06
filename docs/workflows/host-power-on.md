<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure host power on

Set a host's out-of-band power-on mode and credentials, then read them back.

**Requires:** a power-on method configured on the hosts (IPMI, Wake-on-LAN or a custom script).

Workflow `host-power-on`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-HostPowerOn.ps1`](../../powershell/HostsAndPools/Invoke-HostPowerOn.ps1)

```powershell
function Invoke-HostPowerOn {
    <#
    .SYNOPSIS
        Configure host power on.
    .DESCRIPTION
        Set a host's out-of-band power-on mode and credentials, then read them back.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1

    # Mode and config travel together — host.set_power_on_mode takes both in one call, because the
    # config carries the out-of-band credentials the mode needs. The module exposes only
    # Set-XenHost -PowerOnMode (no -PowerOnConfig), so this calls the method directly over JSON-RPC,
    # the same way the events example does for the missing event cmdlet. Still pure PowerShell: no
    # [XenAPI.*]:: statics, and Connect has already trusted the server's certificate.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
    # modes were removed from the real power-on plugin and fail the moment host.power_on is actually
    # called ("{mode} script has been removed").
    Invoke-XenMethod -Session $session -Method 'host.set_power_on_mode' -Params @(
        $xenHost.opaque_ref, 'wake-on-lan', @{})
    $updated = Get-XenHost -Ref $xenHost.opaque_ref
    Write-Host "Power-on mode:  $($updated.power_on_mode)"
    foreach ($k in ($updated.power_on_config.Keys | Sort-Object)) {
        Write-Host "  $k = $($updated.power_on_config[$k])"
    }

    Invoke-XenMethod -Session $session -Method 'host.set_power_on_mode' -Params @($xenHost.opaque_ref, '', @{})
    Write-Host "OK: host-power-on"
    Disconnect-XenServer -Session $session
}
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
OK: host-power-on
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/host-power-on.sh`](../../cli/hosts-and-pools/host-power-on.sh)

```bash
# Configure host power on.
#
# Set a host's out-of-band power-on mode and credentials, then read them back.
#
# Run it:
#   ./workflows.sh host-power-on https://xenserver root "$password"

host_power_on() {
    h=$(first_host)
    # Mode and config travel together: the config carries the credentials the mode needs.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
    # modes were removed from the real power-on plugin and fail the moment host-power-on is actually
    # called ("<mode> script has been removed").
    xe host-set-power-on-mode uuid=$h power-on-mode=wake-on-lan
    echo "Power-on mode:  $(xe host-param-get uuid=$h param-name=power-on-mode)"

    xe host-set-power-on-mode uuid=$h power-on-mode=
    echo "OK: host-power-on"
}
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
OK: host-power-on
```

</details>

## Python

Source: [`python/hosts_and_pools/host_power_on.py`](../../python/hosts_and_pools/host_power_on.py)

```python
"""Configure host power on.

Set a host's out-of-band power-on mode and credentials, then read them back.
"""

from connection import connect


def host_power_on(url, username, password):
    """Set a host's out-of-band power-on mode and credentials, then read them back."""
    session = connect(url, username, password)
    host_ref = session.xenapi.host.get_all()[0]

    # Mode and config travel together: the config carries the credentials the mode needs.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/
    # "DRAC" modes were removed from the real power-on plugin and fail the moment host.power_on
    # is actually called.
    session.xenapi.host.set_power_on_mode(host_ref, "wake-on-lan", {})
    print("Power-on mode:  %s" % session.xenapi.host.get_power_on_mode(host_ref))
    for k, v in sorted(session.xenapi.host.get_power_on_config(host_ref).items()):
        print("  %s = %s" % (k, v))

    session.xenapi.host.set_power_on_mode(host_ref, "", {})
    print("OK: host-power-on")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
OK: host-power-on
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/HostPowerOn.cs`](../../csharp/HostsAndPools/HostPowerOn.cs)

```csharp
/// <summary>
/// Set a host's out-of-band power-on mode and credentials, then read them back.
/// </summary>
public static void HostPowerOn(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var hostRef = Host.get_all(session).First().opaque_ref;

    // Mode and config travel together: the config carries the credentials the mode needs.
    // "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
    // modes were removed from the real power-on plugin and fail the moment host.power_on is actually
    // called ("{mode} script has been removed").
    Host.set_power_on_mode(session, hostRef, "wake-on-lan", new Dictionary<string, string>());
    Console.WriteLine($"Power-on mode:  {Host.get_power_on_mode(session, hostRef)}");
    foreach (var kv in Host.get_power_on_config(session, hostRef))
        Console.WriteLine($"  {kv.Key} = {kv.Value}");

    Host.set_power_on_mode(session, hostRef, "", new Dictionary<string, string>());
    Console.WriteLine("OK: host-power-on");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
OK: host-power-on
```

</details>

## Go

Source: [`go/host_power_on.go`](../../go/host_power_on.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// hostPowerOn - Configure host power on.
//
// Set a host's out-of-band power-on mode and credentials, then read them back.
func hostPowerOn(url, user, password string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	hostRef := hosts[0]

	// Mode and config travel together: the config carries the credentials the mode needs.
	// "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/
	// "DRAC" modes were removed from the real power-on plugin and fail the moment host.power_on is
	// actually called ("{mode} script has been removed").
	check(xenapi.Host.SetPowerOnMode(session, hostRef, "wake-on-lan", map[string]string{}))
	mode, _ := xenapi.Host.GetPowerOnMode(session, hostRef)
	fmt.Printf("Power-on mode:  %s\n", mode)
	cfg, _ := xenapi.Host.GetPowerOnConfig(session, hostRef)
	for k, v := range cfg {
		fmt.Printf("  %s = %s\n", k, v)
	}

	check(xenapi.Host.SetPowerOnMode(session, hostRef, "", map[string]string{}))
	fmt.Println("OK: host-power-on")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
OK: host-power-on
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/HostPowerOn.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/HostPowerOn.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import java.util.HashMap;
import java.util.Map;
import java.util.TreeMap;

import static com.xenserver.samples.PoolConnection.connect;

public final class HostPowerOn {
    private HostPowerOn() {
    }

    /**
     * Configure host power on.
     *
     * <p>Set a host's out-of-band power-on mode and credentials, then read them back.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Host host = Host.getAll(conn).iterator().next();

        // Mode and config travel together: the config carries the credentials the mode needs.
        // "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
        // modes were removed from the real power-on plugin and fail the moment host.power_on is actually
        // called.
        Map<String, String> cfg = new HashMap<>();
        host.setPowerOnMode(conn, "wake-on-lan", cfg);
        System.out.println("Power-on mode:  " + host.getPowerOnMode(conn));
        for (Map.Entry<String, String> e : new TreeMap<>(host.getPowerOnConfig(conn)).entrySet()) {
            System.out.println("  " + e.getKey() + " = " + e.getValue());
        }

        host.setPowerOnMode(conn, "", new HashMap<String, String>());
        System.out.println("OK: host-power-on");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
OK: host-power-on
```

</details>
