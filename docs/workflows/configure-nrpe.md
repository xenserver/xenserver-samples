<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure NRPE monitoring

Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read its status and configuration, enable it and permit a monitoring host, then read it back.

Workflow `configure-nrpe`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ConfigureNrpe.ps1`](../../powershell/HostsAndPools/Invoke-ConfigureNrpe.ps1)

```powershell
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
```

<details><summary>Example output</summary>

```text
sdk-host1: NRPE status before: inactive disabled
  status after:  active enabled
  allowed hosts: 127.0.0.1,::1,192.0.2.60
sdk-host2: NRPE status before: inactive disabled
  status after:  active enabled
  allowed hosts: 127.0.0.1,::1,192.0.2.60
OK: configure-nrpe
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/configure-nrpe.sh`](../../cli/hosts-and-pools/configure-nrpe.sh)

```bash
# Configure NRPE monitoring.
#
# Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read its status
# and configuration, enable it and permit a monitoring host, then read it back.
#
# Run it:
#   ./workflows.sh configure-nrpe https://xenserver root "$password"

# host-call-plugin is per-host - there is no pool-wide fan-out for plugin calls, unlike pool-enable-ssh -
# so configure every host, and restore each one to exactly the state (enabled or not, and its
# configuration) it was found in afterwards.
configure_nrpe() {
    for h in $(each_csv "$(xe host-list --minimal)"); do
        # Capture what we're about to change, to put back afterwards.
        status_before=$(xe host-call-plugin host-uuid=$h plugin=nrpe fn=status)
        was_enabled=false
        [ "${status_before##* }" = "enabled" ] && was_enabled=true
        config_before=$(xe host-call-plugin host-uuid=$h plugin=nrpe fn=get-config)
        allowed_hosts_before=$(echo "$config_before" | sed -n 's/^allowed_hosts: *//p')
        debug_before=$(echo "$config_before" | sed -n 's/^debug: *//p')
        ssl_logging_before=$(echo "$config_before" | sed -n 's/^ssl_logging: *//p')

        echo "$(xe host-param-get uuid=$h param-name=name-label): NRPE status before: $status_before"
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=enable >/dev/null
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=set-config \
            args:allowed_hosts=127.0.0.1,::1,192.0.2.60 args:debug=0 args:ssl_logging=0x00 >/dev/null
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=restart >/dev/null
        echo "  status after:  $(xe host-call-plugin host-uuid=$h plugin=nrpe fn=status)"

        # Restore exactly what was found, rather than always disabling: a host that already had NRPE
        # enabled and configured should not be left changed.
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=set-config \
            "args:allowed_hosts=$allowed_hosts_before" "args:debug=$debug_before" "args:ssl_logging=$ssl_logging_before" >/dev/null
        if $was_enabled; then
            xe host-call-plugin host-uuid=$h plugin=nrpe fn=restart >/dev/null
        else
            xe host-call-plugin host-uuid=$h plugin=nrpe fn=disable >/dev/null
        fi
    done
    echo "OK: configure-nrpe"
}
```

<details><summary>Example output</summary>

```text
sdk-host1: NRPE status before: active disabled
  status after:  active enabled
sdk-host2: NRPE status before: active disabled
  status after:  active enabled
OK: configure-nrpe
```

</details>

## Python

Source: [`python/hosts_and_pools/configure_nrpe.py`](../../python/hosts_and_pools/configure_nrpe.py)

```python
"""Configure NRPE monitoring.

Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read
its status and configuration, enable it and permit a monitoring host, then read it back.
"""

from connection import connect


def configure_nrpe(url, username, password):
    """Enable the NRPE agent on every host and allow a monitoring host, through the nrpe plugin.

    host.call_plugin is per-host - there is no pool-wide fan-out for plugin calls the way there is
    for pool.enable_ssh - so configure every host in the pool, and restore each one to exactly the
    state (enabled or not, and its configuration) it was found in afterwards."""
    session = connect(url, username, password)
    for host in session.xenapi.host.get_all():
        def nrpe(fn, args=None, host=host):
            return session.xenapi.host.call_plugin(host, "nrpe", fn, args or {})
        label = session.xenapi.host.get_name_label(host)

        # Capture what we're about to change, to put back afterwards: whether NRPE was already
        # enabled, and its allowed_hosts/debug/ssl_logging settings.
        status_before = nrpe("status").strip()
        was_enabled = status_before.split()[-1] == "enabled"
        before_config = {}
        for line in nrpe("get-config").split("\n"):
            key, sep, value = line.partition(":")
            if sep and key.strip() in ("allowed_hosts", "debug", "ssl_logging"):
                before_config[key.strip()] = value.strip()

        print("%s: NRPE status before: %s" % (label, status_before))
        nrpe("enable")
        nrpe("set-config", {"allowed_hosts": "127.0.0.1,::1,192.0.2.60", "debug": "0", "ssl_logging": "0x00"})
        nrpe("restart")
        print("  status after:  %s" % nrpe("status").strip())
        for line in nrpe("get-config").split("\n"):
            if line.startswith("allowed_hosts:"):
                print("  allowed hosts: %s" % line.split(":", 1)[1].strip())

        # Restore exactly what was found, rather than always disabling: a host that already had NRPE
        # enabled and configured should not be left changed.
        nrpe("set-config", before_config)
        if was_enabled:
            nrpe("restart")
        else:
            nrpe("disable")
    print("OK: configure-nrpe")
    session.logout()
```

<details><summary>Example output</summary>

```text
sdk-host1: NRPE status before: inactive disabled
  status after:  active enabled
  allowed hosts: 127.0.0.1,::1,192.0.2.60
sdk-host2: NRPE status before: inactive disabled
  status after:  active enabled
  allowed hosts: 127.0.0.1,::1,192.0.2.60
OK: configure-nrpe
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/ConfigureNrpe.cs`](../../csharp/HostsAndPools/ConfigureNrpe.cs)

```csharp
/// <summary>
/// Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read its
/// status and configuration, enable it and permit a monitoring host, then read it back.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureNrpe("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ConfigureNrpe(string url, string user, string password)
{
    var session = Connect(url, user, password);
    // host.call_plugin is per-host - there is no pool-wide fan-out for plugin calls the way there is
    // for pool.enable_ssh - so configure every host in the pool, and restore each one to exactly the
    // state (enabled or not, and its configuration) it was found in afterwards.
    foreach (var host in Host.get_all(session))
    {
        string Nrpe(string fn, Dictionary<string, string> args) =>
            Host.call_plugin(session, host.opaque_ref, "nrpe", fn, args);
        var label = Host.get_name_label(session, host.opaque_ref);

        // Capture what we're about to change, to put back afterwards.
        var statusBefore = Nrpe("status", new()).Trim();
        var wasEnabled = statusBefore.Split(' ', StringSplitOptions.RemoveEmptyEntries).Last() == "enabled";
        var beforeConfig = new Dictionary<string, string>();
        foreach (var line in Nrpe("get-config", new()).Split('\n'))
        {
            var parts = line.Split(':', 2);
            if (parts.Length == 2 && new[] { "allowed_hosts", "debug", "ssl_logging" }.Contains(parts[0].Trim()))
                beforeConfig[parts[0].Trim()] = parts[1].Trim();
        }

        Console.WriteLine($"{label}: NRPE status before: {statusBefore}");
        Nrpe("enable", new());
        Nrpe("set-config", new()
        {
            ["allowed_hosts"] = "127.0.0.1,::1,192.0.2.60",
            ["debug"] = "0",
            ["ssl_logging"] = "0x00",
        });
        Nrpe("restart", new());
        Console.WriteLine($"  status after:  {Nrpe("status", new()).Trim()}");
        foreach (var line in Nrpe("get-config", new()).Split('\n'))
            if (line.StartsWith("allowed_hosts:"))
                Console.WriteLine($"  allowed hosts: {line.Split(':', 2)[1].Trim()}");

        // Restore exactly what was found, rather than always disabling: a host that already had
        // NRPE enabled and configured should not be left changed.
        Nrpe("set-config", beforeConfig);
        if (wasEnabled)
            Nrpe("restart", new());
        else
            Nrpe("disable", new());
    }
    Console.WriteLine("OK: configure-nrpe");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
sdk-host1: NRPE status before: inactive disabled
  status after:  active enabled
  allowed hosts: 127.0.0.1,::1,192.0.2.60
sdk-host2: NRPE status before: inactive disabled
  status after:  active enabled
  allowed hosts: 127.0.0.1,::1,192.0.2.60
OK: configure-nrpe
```

</details>

## Go

Source: [`go/configure_nrpe.go`](../../go/configure_nrpe.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// configureNrpe - Configure NRPE monitoring.
//
// Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read
// its status and configuration, enable it and permit a monitoring host, then read it back.
//
// host.call_plugin is per-host - there is no pool-wide fan-out for plugin calls the way there is
// for pool.enable_ssh - so configure every host in the pool, and restore each one to exactly the
// state (enabled or not, and its configuration) it was found in afterwards.
func configureNrpe(url, user, password string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	for _, host := range hosts {
		nrpe := func(fn string, args map[string]string) string {
			r, e := xenapi.Host.CallPlugin(session, host, "nrpe", fn, args)
			check(e)
			return r
		}
		label, _ := xenapi.Host.GetNameLabel(session, host)

		// Capture what we're about to change, to put back afterwards.
		statusBefore := strings.TrimSpace(nrpe("status", map[string]string{}))
		statusWords := strings.Fields(statusBefore)
		wasEnabled := statusWords[len(statusWords)-1] == "enabled"
		beforeConfig := map[string]string{}
		for _, line := range strings.Split(nrpe("get-config", map[string]string{}), "\n") {
			parts := strings.SplitN(line, ":", 2)
			if len(parts) == 2 {
				key := strings.TrimSpace(parts[0])
				if key == "allowed_hosts" || key == "debug" || key == "ssl_logging" {
					beforeConfig[key] = strings.TrimSpace(parts[1])
				}
			}
		}

		fmt.Printf("%s: NRPE status before: %s\n", label, statusBefore)
		nrpe("enable", map[string]string{})
		nrpe("set-config", map[string]string{"allowed_hosts": "127.0.0.1,::1,192.0.2.60", "debug": "0", "ssl_logging": "0x00"})
		nrpe("restart", map[string]string{})
		fmt.Printf("  status after:  %s\n", strings.TrimSpace(nrpe("status", map[string]string{})))
		for _, line := range strings.Split(nrpe("get-config", map[string]string{}), "\n") {
			if strings.HasPrefix(line, "allowed_hosts:") {
				fmt.Printf("  allowed hosts: %s\n", strings.TrimSpace(strings.SplitN(line, ":", 2)[1]))
			}
		}

		// Restore exactly what was found, rather than always disabling: a host that already had NRPE
		// enabled and configured should not be left changed.
		nrpe("set-config", beforeConfig)
		if wasEnabled {
			nrpe("restart", map[string]string{})
		} else {
			nrpe("disable", map[string]string{})
		}
	}
	fmt.Println("OK: configure-nrpe")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
sdk-host1: NRPE status before: inactive disabled
  status after:  active enabled
  allowed hosts: 127.0.0.1,::1,192.0.2.60
sdk-host2: NRPE status before: inactive disabled
  status after:  active enabled
  allowed hosts: 127.0.0.1,::1,192.0.2.60
OK: configure-nrpe
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureNrpe.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureNrpe.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import java.util.Arrays;
import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureNrpe {
    private ConfigureNrpe() {
    }

    /**
     * Configure NRPE monitoring.
     *
     * <p>Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read
     * its status and configuration, enable it and permit a monitoring host, then read it back.
     *
     * <p>host.callPlugin is per-host - there is no pool-wide fan-out for plugin calls the way there is for
     * pool.enableSsh - so configure every host in the pool, and restore each one to exactly the state
     * (enabled or not, and its configuration) it was found in afterwards.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureNrpe.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            for (Host host : Host.getAll(conn)) {
                String label = host.getNameLabel(conn);

                // Capture what we're about to change, to put back afterwards.
                String statusBefore = host.callPlugin(conn, "nrpe", "status", new java.util.HashMap<>()).trim();
                String[] statusWords = statusBefore.split("\\s+");
                boolean wasEnabled = statusWords[statusWords.length - 1].equals("enabled");
                Map<String, String> beforeConfig = new java.util.HashMap<>();
                for (String line : host.callPlugin(conn, "nrpe", "get-config", new java.util.HashMap<>()).split("\n")) {
                    String[] parts = line.split(":", 2);
                    if (parts.length == 2
                            && Arrays.asList("allowed_hosts", "debug", "ssl_logging").contains(parts[0].trim()))
                        beforeConfig.put(parts[0].trim(), parts[1].trim());
                }

                System.out.println(label + ": NRPE status before: " + statusBefore);
                host.callPlugin(conn, "nrpe", "enable", new java.util.HashMap<>());
                Map<String, String> cfg = new java.util.HashMap<>();
                cfg.put("allowed_hosts", "127.0.0.1,::1,192.0.2.60");
                cfg.put("debug", "0");
                cfg.put("ssl_logging", "0x00");
                host.callPlugin(conn, "nrpe", "set-config", cfg);
                host.callPlugin(conn, "nrpe", "restart", new java.util.HashMap<>());
                System.out.println("  status after:  "
                        + host.callPlugin(conn, "nrpe", "status", new java.util.HashMap<>()).trim());
                for (String line : host.callPlugin(conn, "nrpe", "get-config", new java.util.HashMap<>()).split("\n")) {
                    if (line.startsWith("allowed_hosts:"))
                        System.out.println("  allowed hosts: " + line.split(":", 2)[1].trim());
                }

                // Restore exactly what was found, rather than always disabling: a host that already had
                // NRPE enabled and configured should not be left changed.
                host.callPlugin(conn, "nrpe", "set-config", beforeConfig);
                if (wasEnabled)
                    host.callPlugin(conn, "nrpe", "restart", new java.util.HashMap<>());
                else
                    host.callPlugin(conn, "nrpe", "disable", new java.util.HashMap<>());
            }
            System.out.println("OK: configure-nrpe");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
sdk-host2: NRPE status before: inactive disabled
  status after:  active enabled
  allowed hosts: 127.0.0.1,::1,192.0.2.60
sdk-host1: NRPE status before: inactive disabled
  status after:  active enabled
  allowed hosts: 127.0.0.1,::1,192.0.2.60
OK: configure-nrpe
```

</details>
