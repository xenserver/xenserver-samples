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

    # Save the original mode and config so the example restores the host to how it found it, not to a
    # blank "no power-on configured" state.
    $originalMode = $xenHost.power_on_mode
    $originalConfig = $xenHost.power_on_config

    # Mode and config travel together — host.set_power_on_mode takes both in one call, because the
    # config carries the out-of-band credentials the mode needs. The module exposes only
    # Set-XenHost -PowerOnMode (no -PowerOnConfig), so this calls the method directly over JSON-RPC,
    # the same way the events example does for the missing event cmdlet. Still pure PowerShell: no
    # [XenAPI.*]:: statics, and Connect has already trusted the server's certificate.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
    # modes were removed from the real power-on plugin and fail the moment host.power_on is actually
    # called ("{mode} script has been removed").
    Invoke-XenMethod -Session $session -Method 'host.set_power_on_mode' -Params @(
        $xenHost.opaque_ref, 'wake-on-lan', @{}) | Out-Null
    $updated = Get-XenHost -Ref $xenHost
    Write-Host "Power-on mode:  $($updated.power_on_mode)"
    if ($updated.power_on_config.Count -gt 0) {
        foreach ($k in ($updated.power_on_config.Keys | Sort-Object)) {
            Write-Host "  $k = $($updated.power_on_config[$k])"
        }
    } else {
        Write-Host "  no credentials needed"
    }

    Invoke-XenMethod -Session $session -Method 'host.set_power_on_mode' -Params @(
        $xenHost.opaque_ref, $originalMode, $originalConfig) | Out-Null
    $restored = (Get-XenHost -Ref $xenHost).power_on_mode
    Write-Host "Restored power-on mode: $(if ($restored) { $restored } else { '(none)' })"
    Write-Host "OK: host-power-on"
    Disconnect-XenServer -Session $session
}
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
  no credentials needed
Restored power-on mode: (none)
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
    local original_mode original_config config kv restored
    original_mode=$(xe host-param-get uuid=$h param-name=power-on-mode)
    # A map field prints as "key: value; key2: value2" (empty if there is none) - keep the raw form so
    # it can be split into key=value pairs again below, to restore it rather than just clearing it.
    original_config=$(xe host-param-get uuid=$h param-name=power-on-config)

    # Mode and config travel together: the config carries the credentials the mode needs.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
    # modes were removed from the real power-on plugin and fail the moment host-power-on is actually
    # called ("<mode> script has been removed").
    xe host-set-power-on-mode uuid=$h power-on-mode=wake-on-lan
    echo "Power-on mode:  $(xe host-param-get uuid=$h param-name=power-on-mode)"
    config=$(set_to_csv "$(xe host-param-get uuid=$h param-name=power-on-config)")
    if [ -n "$config" ]; then
        for kv in $(each_csv "$config"); do echo "  ${kv/: /=}"; done
    else
        echo "  no credentials needed"
    fi

    # power-on-mode and power-on-config are both read-only fields (no param-set/param-add of their own) -
    # host-set-power-on-mode is the only way to change either, and it takes both together, so restore the
    # original config the same way it was read, as power-on-config:key=value arguments.
    local -a restore=(uuid=$h power-on-mode="$original_mode")
    config=$(set_to_csv "$original_config")
    if [ -n "$config" ]; then
        for kv in $(each_csv "$config"); do restore+=("power-on-config:${kv/: /=}"); done
    fi
    xe host-set-power-on-mode "${restore[@]}"
    restored=$(xe host-param-get uuid=$h param-name=power-on-mode)
    echo "Restored power-on mode: ${restored:-(none)}"
    ok host-power-on
}
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
  no credentials needed
Restored power-on mode: (none)
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

    # Save the original mode and config so the example restores the host to how it found it, not to
    # a blank "no power-on configured" state.
    original_mode = session.xenapi.host.get_power_on_mode(host_ref)
    original_config = session.xenapi.host.get_power_on_config(host_ref)

    # Mode and config travel together: the config carries the credentials the mode needs.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/
    # "DRAC" modes were removed from the real power-on plugin and fail the moment host.power_on
    # is actually called.
    session.xenapi.host.set_power_on_mode(host_ref, "wake-on-lan", {})
    print("Power-on mode:  %s" % session.xenapi.host.get_power_on_mode(host_ref))
    config = session.xenapi.host.get_power_on_config(host_ref)
    if config:
        for k, v in sorted(config.items()):
            print("  %s = %s" % (k, v))
    else:
        print("  no credentials needed")

    session.xenapi.host.set_power_on_mode(host_ref, original_mode, original_config)
    print("Restored power-on mode: %s" % (session.xenapi.host.get_power_on_mode(host_ref) or "(none)"))
    print("OK: host-power-on")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
  no credentials needed
Restored power-on mode: (none)
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
    var hostRef = Host.get_all(session).First();

    // Save the original mode and config so the example restores the host to how it found it, not
    // to a blank "no power-on configured" state.
    var originalMode = Host.get_power_on_mode(session, hostRef);
    var originalConfig = Host.get_power_on_config(session, hostRef);

    // Mode and config travel together: the config carries the credentials the mode needs.
    // "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
    // modes were removed from the real power-on plugin and fail the moment host.power_on is actually
    // called ("{mode} script has been removed").
    Host.set_power_on_mode(session, hostRef, "wake-on-lan", new Dictionary<string, string>());
    Console.WriteLine($"Power-on mode:  {Host.get_power_on_mode(session, hostRef)}");
    var config = Host.get_power_on_config(session, hostRef);
    if (config.Count > 0)
        foreach (var kv in config)
            Console.WriteLine($"  {kv.Key} = {kv.Value}");
    else
        Console.WriteLine("  no credentials needed");

    Host.set_power_on_mode(session, hostRef, originalMode, originalConfig);
    var restored = Host.get_power_on_mode(session, hostRef);
    Console.WriteLine($"Restored power-on mode: {(string.IsNullOrEmpty(restored) ? "(none)" : restored)}");
    Console.WriteLine("OK: host-power-on");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
  no credentials needed
Restored power-on mode: (none)
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
	defer session.Logout()
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	hostRef := hosts[0]

	// Save the original mode and config so the example restores the host to how it found it, not to a
	// blank "no power-on configured" state.
	originalMode, err := xenapi.Host.GetPowerOnMode(session, hostRef)
	check(err)
	originalConfig, err := xenapi.Host.GetPowerOnConfig(session, hostRef)
	check(err)

	// Mode and config travel together: the config carries the credentials the mode needs.
	// "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/
	// "DRAC" modes were removed from the real power-on plugin and fail the moment host.power_on is
	// actually called ("{mode} script has been removed").
	check(xenapi.Host.SetPowerOnMode(session, hostRef, "wake-on-lan", map[string]string{}))
	mode, _ := xenapi.Host.GetPowerOnMode(session, hostRef)
	fmt.Printf("Power-on mode:  %s\n", mode)
	cfg, _ := xenapi.Host.GetPowerOnConfig(session, hostRef)
	if len(cfg) > 0 {
		for k, v := range cfg {
			fmt.Printf("  %s = %s\n", k, v)
		}
	} else {
		fmt.Println("  no credentials needed")
	}

	check(xenapi.Host.SetPowerOnMode(session, hostRef, originalMode, originalConfig))
	restored, _ := xenapi.Host.GetPowerOnMode(session, hostRef)
	if restored == "" {
		restored = "(none)"
	}
	fmt.Printf("Restored power-on mode: %s\n", restored)
	fmt.Println("OK: host-power-on")
}
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
  no credentials needed
Restored power-on mode: (none)
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

        // Save the original mode and config so the example restores the host to how it found it, not
        // to a blank "no power-on configured" state.
        String originalMode = host.getPowerOnMode(conn);
        Map<String, String> originalConfig = host.getPowerOnConfig(conn);

        // Mode and config travel together: the config carries the credentials the mode needs.
        // "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
        // modes were removed from the real power-on plugin and fail the moment host.power_on is actually
        // called.
        Map<String, String> cfg = new HashMap<>();
        host.setPowerOnMode(conn, "wake-on-lan", cfg);
        System.out.println("Power-on mode:  " + host.getPowerOnMode(conn));
        Map<String, String> config = host.getPowerOnConfig(conn);
        if (!config.isEmpty()) {
            for (Map.Entry<String, String> e : new TreeMap<>(config).entrySet()) {
                System.out.println("  " + e.getKey() + " = " + e.getValue());
            }
        } else {
            System.out.println("  no credentials needed");
        }

        host.setPowerOnMode(conn, originalMode, originalConfig);
        String restored = host.getPowerOnMode(conn);
        System.out.println("Restored power-on mode: " + (restored.isEmpty() ? "(none)" : restored));
        System.out.println("OK: host-power-on");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Power-on mode:  wake-on-lan
  no credentials needed
Restored power-on mode: (none)
OK: host-power-on
```

</details>
