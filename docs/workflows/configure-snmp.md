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
        a community string and a trap destination, read it back, then put the original configuration back.
    .EXAMPLE
        Invoke-ConfigureSnmp -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$TrapDestination = "192.0.2.50"
    )
    # nmss is the list of real trap destinations SNMP notifications go to - an empty list never
    # configures where traps actually go, which is the whole point of "configure SNMP monitoring".
    # Plugin calls are per-host, so configure every host, and restore each one to what it had before,
    # rather than assuming it was disabled.
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
        # Keep the host's own configuration so it can be put back, rather than left disabled.
        $before = (($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn get-config -Args @{} -PassThru) | ConvertFrom-Json).result
        # The plugin reports a refused config in its answer, not as an API error: check it.
        $answer = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn set-config `
            -Args @{ config = $configJson } -PassThru) | ConvertFrom-Json
        if ($answer.code -ne 0) { throw "set-config refused the configuration: $($answer.message)" }
        $status = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn status -Args @{} -PassThru) | ConvertFrom-Json
        $cfg = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn get-config -Args @{} -PassThru) | ConvertFrom-Json
        Write-Host "$($xenHost.name_label): SNMP enabled: $($status.result.enabled) / $($status.result.active)"
        $trapAddress = if (@($cfg.result.nmss).Count -gt 0) { $cfg.result.nmss[0].address } else { "(none)" }
        Write-Host "  community: $($cfg.result.agent.community), trap destination: $trapAddress"
        $beforeJson = [string]($before | ConvertTo-Json -Compress -Depth 5)
        $restore = ($xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin snmp -Fn set-config `
            -Args @{ config = $beforeJson } -PassThru) | ConvertFrom-Json
        if ($restore.code -ne 0) { throw "set-config refused to restore the configuration: $($restore.message)" }
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
# community string and trap destination, read the configuration and running status back, then put the
# host's original configuration back.
#
# Run it:
#   ./workflows.sh configure-snmp https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   trap_destination (192.0.2.50)

# The string value of a JSON key, e.g. json_value '{"agent":{"community":"x"}}' community => x. The plugin's
# JSON may come on one line or pretty-printed over several, but every value read here is quoted, so
# parameter expansion alone (no sed/grep process) finds it either way.
json_value() {
    local json=$1 key=$2 rest
    rest=${json#*\"$key\"}
    rest=${rest#*:}
    rest=${rest#*\"}
    echo "${rest%%\"*}"
}

# The JSON *object* value of a key (e.g. "result", the config a get-config answer wraps), brace-matched so
# the object's own nested braces don't confuse the search - unlike json_value, which only reads a quoted
# string. Only {}-depth is tracked, not []: a "nmss":[{...}] array's objects still balance the count
# correctly, since the brackets around them never change it. While inside a quoted string, braces don't
# count at all (in_str), and a backslash-escaped quote doesn't end the string early either.
json_object() {
    local json=$1 key=$2 rest depth=0 i c prev="" in_str="" obj=""
    rest=${json#*\"$key\"}
    rest=${rest#*:}
    rest="${rest#"${rest%%[![:space:]]*}"}"
    [ "${rest:0:1}" = "{" ] || return 1
    for ((i = 0; i < ${#rest}; i++)); do
        c=${rest:i:1}
        obj+="$c"
        if [ -n "$in_str" ]; then
            [ "$c" = '"' ] && [ "$prev" != '\' ] && in_str=""
            prev=$c
            continue
        fi
        case "$c" in
            '"') in_str=1 ;;
            '{') depth=$((depth + 1)) ;;
            '}') depth=$((depth - 1)); [ "$depth" -eq 0 ] && break ;;
        esac
        prev=$c
    done
    echo "$obj"
}

# trap_destination: nmss is the list of real trap destinations SNMP notifications go to - an empty list
# never configures where traps actually go, which is arguably the main point of "configure SNMP
# monitoring". Plugin calls are per-host, so configure every host, and restore each one to its own
# original configuration afterwards.
configure_snmp() {
    local trap_destination config nms_uuid answer status cfg dest before
    trap_destination=$(param trap_destination "192.0.2.50")
    # Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
    nms_uuid=$(printf '%04x%04x-%04x-4%03x-%04x-%04x%04x%04x' $RANDOM $RANDOM $RANDOM $((RANDOM & 0xfff)) \
        $(( (RANDOM & 0x3fff) | 0x8000 )) $RANDOM $RANDOM $RANDOM)
    config='{"common":{"enabled":"yes","debug_log":"no"},"agent":{"v2c":"yes","v3":"no","community":"sdk-community","user_name":"","authentication_password":"","authentication_protocol":"","privacy_password":"","privacy_protocol":""},"nmss":[{"uuid":"'"$nms_uuid"'","address":"'"$trap_destination"'","port":162,"v2c":"yes","v3":"no","community":"sdk-community","user_name":"","authentication_password":"","authentication_protocol":"","privacy_password":"","privacy_protocol":""}]}'
    for h in $(each_csv "$(remote_xe host-list --minimal)"); do
        # Read the configuration first, to put it back afterwards instead of just disabling.
        before=$(json_object "$(remote_xe host-call-plugin host-uuid=$h plugin=snmp fn=get-config)" result)
        # A real host pretty-prints it over several lines, but xe passes an argument only up to its first
        # line break: put it back on one line (JSON strings never hold a raw line break, so this is safe).
        before=${before//$'\n'/}
        before=${before//$'\r'/}

        # The plugin reports a refused config in its answer, not as an xe error: check it.
        answer=$(remote_xe host-call-plugin host-uuid=$h plugin=snmp fn=set-config "args:config=$config")
        case "$answer" in *'"code": 0'*|*'"code":0'*) ;; *) echo "set-config refused the configuration: $answer" >&2; exit 1 ;; esac
        status=$(remote_xe host-call-plugin host-uuid=$h plugin=snmp fn=status)
        cfg=$(remote_xe host-call-plugin host-uuid=$h plugin=snmp fn=get-config)
        dest=$(json_value "$cfg" address); dest=${dest:-"(none)"}
        echo "$(remote_xe host-param-get uuid=$h param-name=name-label): SNMP enabled: $(json_value "$status" enabled) / $(json_value "$status" active)"
        echo "  community: $(json_value "$cfg" community), trap destination: $dest"
        # Restore: put the host's own configuration back rather than always disabling it.
        answer=$(remote_xe host-call-plugin host-uuid=$h plugin=snmp fn=set-config "args:config=$before")
        case "$answer" in *'"code": 0'*|*'"code":0'*) ;; *) echo "set-config refused restoring the configuration: $answer" >&2; exit 1 ;; esac
    done
    ok configure-snmp
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

## Python

Source: [`python/hosts_and_pools/configure_snmp.py`](../../python/hosts_and_pools/configure_snmp.py)

```python
"""Configure SNMP monitoring.

Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with
a community string and a trap destination, read it back, then put the original configuration back.
"""

import json
import uuid

from connection import connect


def configure_snmp(url, username, password, trap_destination="192.0.2.50"):
    """On every host, through the snmp plugin: read its configuration, enable it with a community
    string and a trap destination, read it back, then put the original configuration back.

    nmss is the list of real trap destinations SNMP notifications go to - an empty list never
    configures where traps actually go, which is the whole point of "configure SNMP monitoring".
    Plugin calls are per-host, so configure every host, and restore each one to what it had
    before, rather than assuming it was disabled."""
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
        # Keep the host's own configuration so it can be put back, rather than left disabled.
        before = snmp("get-config")["result"]
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
        restore = snmp("set-config", {"config": json.dumps(before)})
        if restore["code"] != 0:
            raise RuntimeError("set-config refused to restore the configuration: %s" % restore["message"])
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
/// community string and trap destination, read it back, then put the original configuration back.
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
        // Read the host's own configuration first, so it can be put back afterwards instead of
        // just being switched off.
        using var before = JsonDocument.Parse(Snmp("get-config", new()));
        var previousConfig = before.RootElement.GetProperty("result").GetRawText();
        // The plugin reports a refused config in its answer, not as an API error: check it.
        using (var answer = JsonDocument.Parse(Snmp("set-config", new() { ["config"] = config })))
            if (answer.RootElement.GetProperty("code").GetInt32() != 0)
                throw new InvalidOperationException("set-config refused the configuration: "
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
        // restore
        using var restoreAnswer = JsonDocument.Parse(Snmp("set-config", new() { ["config"] = previousConfig }));
        if (restoreAnswer.RootElement.GetProperty("code").GetInt32() != 0)
            throw new InvalidOperationException("set-config refused to restore the configuration: "
                                + restoreAnswer.RootElement.GetProperty("message").GetString());
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
// Read a host's SNMP configuration through the monitoring plugin, enable it with a community
// string and a trap destination, read the configuration back, then put the original configuration
// back.
//
// nmss is the list of real trap destinations SNMP notifications go to - an empty list never
// configures where traps actually go, which is the whole point of "configure SNMP monitoring".
// Plugin calls are per-host, so configure every host, and restore each one to what it had before
// afterwards.
func configureSnmp(url, user, password, trapDestination string) {
	session := connect(url, user, password)
	defer session.Logout()
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
		// Keep the host's current configuration so it can be put back afterwards, instead of just disabled.
		before := snmp("get-config", map[string]string{})["result"]
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
		beforeJSON, err := json.Marshal(before)
		check(err)
		if answer := snmp("set-config", map[string]string{"config": string(beforeJSON)}); answer["code"] != float64(0) {
			panic(fmt.Sprintf("set-config refused restoring the configuration: %v", answer["message"]))
		}
	}
	fmt.Println("OK: configure-snmp")
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

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureSnmp {
    private static final String RESULT = "result";   // the plugin wraps every answer in it

    private ConfigureSnmp() {
    }

    /**
     * Configure SNMP monitoring.
     *
     * <p>Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it
     * with a community string and a trap destination, read it back, then put the original configuration
     * back.
     *
     * <p>On every host, through the snmp plugin: read its configuration, enable it with a community
     * string and a trap destination, read it back, then put the original configuration back.
     *
     * <p>trapDestination: the "nmss" list must contain at least one non-empty entry pointed at it (an
     * empty list never configures where traps actually go - arguably the main point of "configure SNMP
     * monitoring"). Plugin calls are per-host, so configure every host, and restore each one to what it
     * had before, rather than assuming it was disabled.
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
            ObjectMapper mapper = new ObjectMapper();
            String config = "{\"common\":{\"enabled\":\"yes\",\"debug_log\":\"no\"},"
                + "\"agent\":{\"v2c\":\"yes\",\"v3\":\"no\",\"community\":\"sdk-community\",\"user_name\":\"\","
                + "\"authentication_password\":\"\",\"authentication_protocol\":\"\","
                + "\"privacy_password\":\"\",\"privacy_protocol\":\"\"},"
                // Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
                + "\"nmss\":[{\"uuid\":\"" + UUID.randomUUID() + "\",\"address\":\"" + trapDestination
                + "\",\"port\":162,\"v2c\":\"yes\",\"v3\":\"no\","
                + "\"community\":\"sdk-community\",\"user_name\":\"\",\"authentication_password\":\"\","
                + "\"authentication_protocol\":\"\",\"privacy_password\":\"\",\"privacy_protocol\":\"\"}]}";
            for (Host host : Host.getAll(conn)) {
                // Keep the host's own configuration so it can be put back, rather than left disabled.
                // Parsed with Jackson (already a dependency of the binding) rather than hand-rolled: the
                // result nests an "nmss" array of objects, which a quick string search can't reliably peel
                // off.
                JsonNode before = call(conn, mapper, host, "get-config", Map.of()).path(RESULT);

                Map<String, String> args = new HashMap<>();
                args.put("config", config);
                // The plugin reports a refused config in its answer, not as an API error: check it.
                JsonNode answer = call(conn, mapper, host, "set-config", args);
                if (answer.path("code").asInt() != 0)
                    throw new IllegalStateException(
                        "set-config refused the configuration: " + answer.path("message").asText());
                JsonNode status = call(conn, mapper, host, "status", Map.of()).path(RESULT);
                JsonNode cfg = call(conn, mapper, host, "get-config", Map.of()).path(RESULT);
                String label = host.getNameLabel(conn);
                System.out.println(label + ": SNMP enabled: " + status.path("enabled").asText()
                        + " / " + status.path("active").asText());
                JsonNode nmss = cfg.path("nmss");
                System.out.println("  community: " + cfg.path("agent").path("community").asText()
                        + ", trap destination: "
                        + (nmss.size() > 0 ? nmss.get(0).path("address").asText() : "(none)"));

                // Put back whatever configuration the host had before, rather than leaving it disabled.
                Map<String, String> restore = new HashMap<>();
                restore.put("config", mapper.writeValueAsString(before));
                JsonNode restoreAnswer = call(conn, mapper, host, "set-config", restore);
                if (restoreAnswer.path("code").asInt() != 0)
                    throw new IllegalStateException("set-config refused to restore the configuration: "
                        + restoreAnswer.path("message").asText());
            }
            System.out.println("OK: configure-snmp");
        } finally {
            Session.logout(conn);
        }
    }

    /** One call to the snmp plugin, parsed as JSON - every function it exports answers with JSON. */
    private static JsonNode call(Connection conn, ObjectMapper mapper, Host host, String fn,
            Map<String, String> args) throws Exception {
        return mapper.readTree(host.callPlugin(conn, "snmp", fn, args));
    }
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
