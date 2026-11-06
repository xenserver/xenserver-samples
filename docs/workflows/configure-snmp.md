<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure SNMP monitoring

Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with a community string, then read the configuration and running status back.

Workflow `configure-snmp`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ConfigureSnmp.ps1`](../../powershell/HostsAndPools/Invoke-ConfigureSnmp.ps1)

```powershell
function Invoke-ConfigureSnmp {
    <#
    .SYNOPSIS
        Configure SNMP monitoring.
    .DESCRIPTION
        Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with
        a community string, then read the configuration and running status back.
    .EXAMPLE
        Invoke-ConfigureSnmp -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$TrapDestination = "192.0.2.50"
    )
    # Enable the SNMP agent on every host with a community string and a trap destination, through the
    # snmp plugin.
    #
    # nmss is the list of real trap destinations SNMP notifications go to - an empty list never
    # configures where traps actually go, which is the whole point of "configure SNMP monitoring".
    # Plugin calls are per-host, so configure every host, and restore each one to disabled again
    # afterwards.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $config = @{
        common = @{ enabled = "yes"; debug_log = "no" }
        agent  = @{ v2c = "yes"; v3 = "no"; community = "sdk-community"; user_name = "";
                    authentication_password = ""; authentication_protocol = "";
                    privacy_password = ""; privacy_protocol = "" }
        # Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
        nmss   = @(@{ uuid = [guid]::NewGuid().ToString(); address = $TrapDestination; port = 162; v2c = "yes"; v3 = "no";
                      community = "sdk-community"; user_name = ""; authentication_password = "";
                      authentication_protocol = ""; privacy_password = ""; privacy_protocol = "" })
    }
    $configJson = [string]($config | ConvertTo-Json -Compress -Depth 5)
    foreach ($xenHost in Get-XenHost) {
        # The plugin reports a refused config in its answer, not as an API error: check it.
        $answer = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn set-config `
            -Args @{ config = $configJson } -PassThru) | ConvertFrom-Json
        if ($answer.code -ne 0) { throw "set-config refused the configuration: $($answer.message)" }
        $status = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn status -Args @{} -PassThru) | ConvertFrom-Json
        $cfg = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn get-config -Args @{} -PassThru) | ConvertFrom-Json
        Write-Host "$($xenHost.name_label): SNMP enabled: $($status.result.enabled) / $($status.result.active)"
        $trapAddress = if (@($cfg.result.nmss).Count -gt 0) { $cfg.result.nmss[0].address } else { "(none)" }
        Write-Host "  community: $($cfg.result.agent.community), trap destination: $trapAddress"
        $restoreJson = [string](@{ common = @{ enabled = "no" } } | ConvertTo-Json -Compress -Depth 3)
        $xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn set-config `
            -Args @{ config = $restoreJson } -PassThru | Out-Null   # restore
    }
    Write-Host "OK: configure-snmp"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
sdk-host1: SNMP enabled: enabled / active
  community: sdk-community, trap destination: 192.0.2.50
sdk-host2: SNMP enabled: enabled / active
  community: sdk-community, trap destination: 192.0.2.50
OK: configure-snmp
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/configure-snmp.sh`](../../cli/hosts-and-pools/configure-snmp.sh)

```bash
# Configure SNMP monitoring.
#
# Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with a
# community string, then read the configuration and running status back.
#
# Run it:
#   ./workflows.sh configure-snmp https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   trap_destination (192.0.2.50)

# trap_destination: nmss is the list of real trap destinations SNMP notifications go to - an empty list
# never configures where traps actually go, which is arguably the main point of "configure SNMP
# monitoring". Plugin calls are per-host, so configure every host, and restore each one to disabled again
# afterwards.
configure_snmp() {
    local trap_destination config nms_uuid answer
    trap_destination=$(param trap_destination "192.0.2.50")
    # Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
    nms_uuid=$(printf '%04x%04x-%04x-4%03x-%04x-%04x%04x%04x' $RANDOM $RANDOM $RANDOM $((RANDOM & 0xfff)) \
        $(( (RANDOM & 0x3fff) | 0x8000 )) $RANDOM $RANDOM $RANDOM)
    config='{"common":{"enabled":"yes","debug_log":"no"},"agent":{"v2c":"yes","v3":"no","community":"sdk-community","user_name":"","authentication_password":"","authentication_protocol":"","privacy_password":"","privacy_protocol":""},"nmss":[{"uuid":"'"$nms_uuid"'","address":"'"$trap_destination"'","port":162,"v2c":"yes","v3":"no","community":"sdk-community","user_name":"","authentication_password":"","authentication_protocol":"","privacy_password":"","privacy_protocol":""}]}'
    for h in $(each_csv "$(xe host-list --minimal)"); do
        # The plugin reports a refused config in its answer, not as an xe error: check it.
        answer=$(xe host-call-plugin host-uuid=$h plugin=snmp fn=set-config "args:config=$config")
        case "$answer" in *'"code": 0'*|*'"code":0'*) ;; *) echo "set-config refused the configuration: $answer" >&2; exit 1 ;; esac
        echo "$(xe host-param-get uuid=$h param-name=name-label): SNMP status: $(xe host-call-plugin host-uuid=$h plugin=snmp fn=status)"
        xe host-call-plugin host-uuid=$h plugin=snmp fn=set-config 'args:config={"common":{"enabled":"no"}}' >/dev/null  # restore
    done
    echo "OK: configure-snmp"
}
```

<details><summary>Example output</summary>

```text
sdk-host1: SNMP status: {"code":0,"result":{"enabled":"enabled","active":"active"},"message":null}
sdk-host2: SNMP status: {"code":0,"result":{"enabled":"enabled","active":"active"},"message":null}
OK: configure-snmp
```

</details>

## Python

Source: [`python/hosts_and_pools/configure_snmp.py`](../../python/hosts_and_pools/configure_snmp.py)

```python
"""Configure SNMP monitoring.

Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with
a community string, then read the configuration and running status back.
"""

import json
import uuid

from connection import connect


def configure_snmp(url, username, password, trap_destination="192.0.2.50"):
    """Enable the SNMP agent on every host with a community string and a trap destination, through
    the snmp plugin.

    nmss is the list of real trap destinations SNMP notifications go to - an empty list never
    configures where traps actually go, which is the whole point of "configure SNMP monitoring".
    Plugin calls are per-host, so configure every host, and restore each one to disabled again
    afterwards."""
    session = connect(url, username, password)
    config = {
        "common": {"enabled": "yes", "debug_log": "no"},
        "agent": {"v2c": "yes", "v3": "no", "community": "sdk-community", "user_name": "",
                  "authentication_password": "", "authentication_protocol": "",
                  "privacy_password": "", "privacy_protocol": ""},
        # Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
        "nmss": [{"uuid": str(uuid.uuid4()), "address": trap_destination, "port": 162, "v2c": "yes", "v3": "no",
                  "community": "sdk-community", "user_name": "", "authentication_password": "",
                  "authentication_protocol": "", "privacy_password": "", "privacy_protocol": ""}],
    }
    for host in session.xenapi.host.get_all():
        def snmp(fn, args=None, host=host):
            return json.loads(session.xenapi.host.call_plugin(host, "snmp", fn, args or {}))
        # The plugin reports a refused config in its answer, not as an API error: check it.
        answer = snmp("set-config", {"config": json.dumps(config)})
        if answer["code"] != 0:
            raise RuntimeError("set-config refused the configuration: %s" % answer["message"])
        status = snmp("status")["result"]
        cfg = snmp("get-config")["result"]
        label = session.xenapi.host.get_name_label(host)
        print("%s: SNMP enabled: %s / %s" % (label, status["enabled"], status["active"]))
        print("  community: %s, trap destination: %s"
              % (cfg["agent"]["community"], cfg["nmss"][0]["address"] if cfg["nmss"] else "(none)"))
        snmp("set-config", {"config": json.dumps({"common": {"enabled": "no"}})})  # restore
    print("OK: configure-snmp")
    session.logout()
```

<details><summary>Example output</summary>

```text
sdk-host1: SNMP enabled: enabled / active
  community: sdk-community, trap destination: 192.0.2.50
sdk-host2: SNMP enabled: enabled / active
  community: sdk-community, trap destination: 192.0.2.50
OK: configure-snmp
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/ConfigureSnmp.cs`](../../csharp/HostsAndPools/ConfigureSnmp.cs)

```csharp
/// <summary>
/// Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with a
/// community string, then read the configuration and running status back.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureSnmp("https://xenserver", "root", password, trapDestination: "192.0.2.50");
/// </code>
/// </example>
public static void ConfigureSnmp(string url, string user, string password,
    string trapDestination = "192.0.2.50")
{
    var session = Connect(url, user, password);
    // nmss is the list of real trap destinations SNMP notifications go to - an empty list never
    // configures where traps actually go, which is the whole point of "configure SNMP monitoring".
    var config =
        "{\"common\":{\"enabled\":\"yes\",\"debug_log\":\"no\"}," +
        "\"agent\":{\"v2c\":\"yes\",\"v3\":\"no\",\"community\":\"sdk-community\",\"user_name\":\"\"," +
        "\"authentication_password\":\"\",\"authentication_protocol\":\"\"," +
        "\"privacy_password\":\"\",\"privacy_protocol\":\"\"}," +
        // Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
        $"\"nmss\":[{{\"uuid\":\"{Guid.NewGuid()}\",\"address\":\"{trapDestination}\",\"port\":162,\"v2c\":\"yes\",\"v3\":\"no\"," +
        "\"community\":\"sdk-community\",\"user_name\":\"\",\"authentication_password\":\"\"," +
        "\"authentication_protocol\":\"\",\"privacy_password\":\"\",\"privacy_protocol\":\"\"}]}";
    // Plugin calls are per-host, so configure every host, and restore each one to disabled again
    // afterwards.
    foreach (var host in Host.get_all(session))
    {
        string Snmp(string fn, Dictionary<string, string> args) =>
            Host.call_plugin(session, host, "snmp", fn, args);
        // The plugin reports a refused config in its answer, not as an API error: check it.
        using (var answer = JsonDocument.Parse(Snmp("set-config", new() { ["config"] = config })))
            if (answer.RootElement.GetProperty("code").GetInt32() != 0)
                throw new Exception("set-config refused the configuration: "
                                    + answer.RootElement.GetProperty("message").GetString());
        using var status = JsonDocument.Parse(Snmp("status", new()));
        using var cfg = JsonDocument.Parse(Snmp("get-config", new()));
        var result = status.RootElement.GetProperty("result");
        var agentCfg = cfg.RootElement.GetProperty("result");
        var nmss = agentCfg.GetProperty("nmss");
        var label = Host.get_name_label(session, host);
        Console.WriteLine($"{label}: SNMP enabled: {result.GetProperty("enabled").GetString()} / " +
                          $"{result.GetProperty("active").GetString()}");
        Console.WriteLine($"  community: {agentCfg.GetProperty("agent").GetProperty("community").GetString()}, " +
                          $"trap destination: {(nmss.GetArrayLength() > 0 ? nmss[0].GetProperty("address").GetString() : "(none)")}");
        Snmp("set-config", new() { ["config"] = "{\"common\":{\"enabled\":\"no\"}}" }); // restore
    }
    Console.WriteLine("OK: configure-snmp");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
sdk-host1: SNMP enabled: enabled / active
  community: sdk-community, trap destination: 192.0.2.50
sdk-host2: SNMP enabled: enabled / active
  community: sdk-community, trap destination: 192.0.2.50
OK: configure-snmp
```

</details>

## Go

Source: [`go/configure_snmp.go`](../../go/configure_snmp.go)

```go
package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"

	"go/xenapi"
)

// configureSnmp - Configure SNMP monitoring.
//
// Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it
// with a community string, then read the configuration and running status back.
//
// nmss is the list of real trap destinations SNMP notifications go to - an empty list never
// configures where traps actually go, which is the whole point of "configure SNMP monitoring".
// Plugin calls are per-host, so configure every host, and restore each one to disabled again
// afterwards.
func configureSnmp(url, user, password, trapDestination string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	config := `{"common":{"enabled":"yes","debug_log":"no"},` +
		`"agent":{"v2c":"yes","v3":"no","community":"sdk-community","user_name":"",` +
		`"authentication_password":"","authentication_protocol":"",` +
		// Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
		`"privacy_password":"","privacy_protocol":""},"nmss":[{"uuid":"` + newUUID() + `","address":"` + trapDestination + `",` +
		`"port":162,"v2c":"yes","v3":"no","community":"sdk-community","user_name":"",` +
		`"authentication_password":"","authentication_protocol":"",` +
		`"privacy_password":"","privacy_protocol":""}]}`
	for _, host := range hosts {
		snmp := func(fn string, args map[string]string) map[string]interface{} {
			r, e := xenapi.Host.CallPlugin(session, host, "snmp", fn, args)
			check(e)
			var env map[string]interface{}
			check(json.Unmarshal([]byte(r), &env))
			return env
		}
		// The plugin reports a refused config in its answer, not as an API error: check it.
		if answer := snmp("set-config", map[string]string{"config": config}); answer["code"] != float64(0) {
			panic(fmt.Sprintf("set-config refused the configuration: %v", answer["message"]))
		}
		status := snmp("status", map[string]string{})["result"].(map[string]interface{})
		cfg := snmp("get-config", map[string]string{})["result"].(map[string]interface{})
		agent := cfg["agent"].(map[string]interface{})
		nmss, _ := cfg["nmss"].([]interface{})
		label, _ := xenapi.Host.GetNameLabel(session, host)
		fmt.Printf("%s: SNMP enabled: %v / %v\n", label, status["enabled"], status["active"])
		trap := "(none)"
		if len(nmss) > 0 {
			if first, ok := nmss[0].(map[string]interface{}); ok {
				trap = fmt.Sprintf("%v", first["address"])
			}
		}
		fmt.Printf("  community: %v, trap destination: %s\n", agent["community"], trap)
		snmp("set-config", map[string]string{"config": `{"common":{"enabled":"no"}}`}) // restore
	}
	fmt.Println("OK: configure-snmp")
	session.Logout()
}

// newUUID returns a random (version 4) UUID.
func newUUID() string {
	b := make([]byte, 16)
	_, err := rand.Read(b)
	check(err)
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}
```

<details><summary>Example output</summary>

```text
sdk-host1: SNMP enabled: enabled / active
  community: sdk-community, trap destination: 192.0.2.50
sdk-host2: SNMP enabled: enabled / active
  community: sdk-community, trap destination: 192.0.2.50
OK: configure-snmp
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureSnmp.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureSnmp.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureSnmp {
    private ConfigureSnmp() {
    }

    /**
     * Configure SNMP monitoring.
     *
     * <p>Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it
     * with a community string, then read the configuration and running status back.
     *
     * <p>trap_destination: the "nmss" list must contain at least one non-empty entry pointed at it (an
     * empty list never configures where traps actually go - arguably the main point of "configure SNMP
     * monitoring". Loop every host, same reasoning as configure-nrpe; restore each host to
     * {"common":{"enabled":"no"}} (a partial config - real set-config merges) at the end.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureSnmp.run("https://xenserver", "root", password, "192.0.2.50");
     * }</pre>
     */
    public static void run(String url, String user, String password, String trapDestination)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            String config = "{\"common\":{\"enabled\":\"yes\",\"debug_log\":\"no\"},"
                + "\"agent\":{\"v2c\":\"yes\",\"v3\":\"no\",\"community\":\"sdk-community\",\"user_name\":\"\","
                + "\"authentication_password\":\"\",\"authentication_protocol\":\"\","
                + "\"privacy_password\":\"\",\"privacy_protocol\":\"\"},"
                // Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
                + "\"nmss\":[{\"uuid\":\"" + java.util.UUID.randomUUID() + "\",\"address\":\"" + trapDestination
                + "\",\"port\":162,\"v2c\":\"yes\",\"v3\":\"no\","
                + "\"community\":\"sdk-community\",\"user_name\":\"\",\"authentication_password\":\"\","
                + "\"authentication_protocol\":\"\",\"privacy_password\":\"\",\"privacy_protocol\":\"\"}]}";
            for (Host host : Host.getAll(conn)) {
                Map<String, String> args = new java.util.HashMap<>();
                args.put("config", config);
                // The plugin reports a refused config in its answer, not as an API error: check it.
                String answer = host.callPlugin(conn, "snmp", "set-config", args);
                if (!answer.replace(" ", "").contains("\"code\":0"))
                    throw new RuntimeException("set-config refused the configuration: " + answer);
                String status = host.callPlugin(conn, "snmp", "status", new java.util.HashMap<>());
                String cfg = host.callPlugin(conn, "snmp", "get-config", new java.util.HashMap<>());
                String label = host.getNameLabel(conn);
                System.out.println(label + ": SNMP enabled: " + jsonField(status, "enabled")
                        + " / " + jsonField(status, "active"));
                System.out.println("  community: " + jsonField(cfg, "community")
                        + ", trap destination: " + jsonField(cfg, "address"));
                Map<String, String> restore = new java.util.HashMap<>();
                restore.put("config", "{\"common\":{\"enabled\":\"no\"}}");
                host.callPlugin(conn, "snmp", "set-config", restore); // restore
            }
            System.out.println("OK: configure-snmp");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Minimal extractor for a "key":"value" pair in the SNMP plugin's JSON reply (avoids a JSON
     * dependency).
     */
    private static String jsonField(String json, String key) {
        java.util.regex.Matcher m = java.util.regex.Pattern
            .compile("\"" + key + "\"\\s*:\\s*\"([^\"]*)\"").matcher(json);
        return m.find() ? m.group(1) : "";
    }
}
```

<details><summary>Example output</summary>

```text
sdk-host2: SNMP enabled: enabled / active
  community: sdk-community, trap destination: 192.0.2.50
sdk-host1: SNMP enabled: enabled / active
  community: sdk-community, trap destination: 192.0.2.50
OK: configure-snmp
```

</details>
