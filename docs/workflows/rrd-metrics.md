<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Read RRD performance metrics

Pull recent host performance samples from the RRD archives over the performance-data HTTP API, parse the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space utilisation per host).

Workflow `rrd-metrics`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/RrdMetrics.cs`](../../csharp/HostsAndPools/RrdMetrics.cs)

```csharp
/// <summary>
/// Pull recent host performance samples from the RRD archives over the performance-data HTTP API, parse
/// the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space utilisation
/// per host).
/// </summary>
public static void RrdMetrics(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var nameByUuid = Host.get_all_records(session).Values.ToDictionary(h => h.uuid, h => h.name_label);

    // The RRD time-series isn't a XenAPI call; read rrd_updates over HTTP. Legends look like
    // "AVERAGE:host:<uuid>:<datasource>"; values[] aligns to legend[].
    var start = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - 300;
    using var http = new HttpClient(new HttpClientHandler
    {
        ServerCertificateCustomValidationCallback = (_, _, _, _) => true
    });
    http.DefaultRequestHeaders.Add("accept", "application/json");
    var json = http.GetStringAsync($"{url}/rrd_updates?session_id={session.opaque_ref}&host=true&start={start}").Result;

    using var doc = JsonDocument.Parse(json);
    var legends = doc.RootElement.GetProperty("meta").GetProperty("legend")
        .EnumerateArray().Select(e => e.GetString()!).ToArray();
    var peak = new Dictionary<string, double>();
    foreach (var point in doc.RootElement.GetProperty("data").EnumerateArray())
    {
        var values = point.GetProperty("values");
        for (int k = 0; k < legends.Length; k++)
        {
            var parts = legends[k].Split(':');
            if (parts[1] == "host" && parts[3] == "pvsaccelerator_space_utilization")
            {
                // A host sends each value as a string ("0.0", or "NaN" for a gap in the series).
                var v = values[k].ValueKind == JsonValueKind.String
                    ? double.Parse(values[k].GetString()!, CultureInfo.InvariantCulture)
                    : values[k].GetDouble();
                if (double.IsNaN(v)) continue;
                if (!peak.TryGetValue(parts[2], out var cur) || v > cur) peak[parts[2]] = v;
            }
        }
    }
    foreach (var (uuid, p) in peak)
        Console.WriteLine($"  {nameByUuid[uuid]}: peak PVS cache utilisation {p:F0}%");
    Console.WriteLine("OK: rrd-metrics");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
  sdk-host1: peak PVS cache utilisation 94%
OK: rrd-metrics
```

</details>

## Python

Source: [`python/hosts_and_pools/rrd_metrics.py`](../../python/hosts_and_pools/rrd_metrics.py)

```python
"""Read RRD performance metrics.

Pull recent host performance samples from the RRD archives over the performance-data HTTP API, parse
the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space utilisation
per host).
"""

import json
import ssl
import time
import urllib.request

from connection import connect


def rrd_metrics(url, username, password):
    session = connect(url, username, password)
    # The RRD time-series isn't a XenAPI call; read the last 5 minutes over HTTP from rrd_updates.
    # Legends look like "AVERAGE:host:<uuid>:<datasource>"; values[] aligns to legend[].
    start = int(time.time()) - 300
    req = urllib.request.Request(
        "%s/rrd_updates?session_id=%s&host=true&start=%d" % (url, session._session, start),
        headers={"accept": "application/json"})
    data = json.load(urllib.request.urlopen(req, context=ssl._create_unverified_context()))
    legends = data["meta"]["legend"]

    peak = {}
    for point in data["data"]:
        for k, legend in enumerate(legends):
            parts = legend.split(":")
            if parts[1] == "host" and parts[3] == "pvsaccelerator_space_utilization":
                value = float(point["values"][k])
                if value != value:  # NaN: a gap in the series, not a real sample - never let it stick
                    continue
                if parts[2] not in peak or value > peak[parts[2]]:
                    peak[parts[2]] = value
    for host in session.xenapi.host.get_all_records().values():
        if host["uuid"] in peak:
            print("  %s: peak PVS cache utilisation %d%%" % (host["name_label"], peak[host["uuid"]]))
    print("OK: rrd-metrics")
    session.logout()
```

<details><summary>Example output</summary>

```text
  sdk-host1: peak PVS cache utilisation 94%
OK: rrd-metrics
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/RrdMetrics.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/RrdMetrics.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.EntityUtils;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class RrdMetrics {
    private RrdMetrics() {
    }

    /**
     * Read RRD performance metrics.
     *
     * <p>Pull recent host performance samples from the RRD archives over the performance-data HTTP API,
     * parse the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space
     * utilisation per host).
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Map<String, String> nameByUuid = new java.util.HashMap<>();
            for (Host.Record h : Host.getAllRecords(conn).values()) nameByUuid.put(h.uuid, h.nameLabel);

            // The RRD time-series isn't a XenAPI call; read rrd_updates over HTTP. Legends look like
            // "AVERAGE:host:<uuid>:<datasource>"; values[] aligns to legend[].
            long start = System.currentTimeMillis() / 1000 - 300;
            HttpGet get = new HttpGet(url + "/rrd_updates?session_id=" + conn.getSessionReference() + "&host=true&start=" + start);
            get.addHeader("accept", "application/json");
            String body;
            try (CloseableHttpClient http = trustingHttpClient()) {
                body = http.execute(get, resp -> EntityUtils.toString(resp.getEntity()));
            }
            JsonNode root = new ObjectMapper().readTree(body);
            JsonNode legends = root.get("meta").get("legend");
            Map<String, Double> peak = new java.util.HashMap<>();
            for (JsonNode point : root.get("data")) {
                JsonNode values = point.get("values");
                for (int k = 0; k < legends.size(); k++) {
                    String[] parts = legends.get(k).asText().split(":");
                    if (parts[1].equals("host") && parts[3].equals("pvsaccelerator_space_utilization")) {
                        double value = values.get(k).asDouble();
                        if (Double.isNaN(value)) continue; // a gap in the series, not a real sample
                        peak.merge(parts[2], value, Math::max);
                    }
                }
            }
            for (Map.Entry<String, Double> e : peak.entrySet())
                System.out.printf("  %s: peak PVS cache utilisation %.0f%%%n", nameByUuid.get(e.getKey()), e.getValue());
            System.out.println("OK: rrd-metrics");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
  sdk-host1: peak PVS cache utilisation 94%
OK: rrd-metrics
```

</details>

## Go

Source: [`go/rrd_metrics.go`](../../go/rrd_metrics.go)

```go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"go/xenapi"
)

// rrdMetrics - Read RRD performance metrics.
//
// Pull recent host performance samples from the RRD archives over the performance-data HTTP API,
// parse the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space
// utilisation per host).
func rrdMetrics(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	nameByUUID := map[string]string{}
	for _, h := range hosts {
		nameByUUID[h.UUID] = h.NameLabel
	}

	// The RRD time-series isn't a XenAPI call; read rrd_updates over HTTP. It needs a session id (the SDK
	// keeps its own private), so obtain one with a small JSON-RPC login. Legends are
	// "AVERAGE:host:<uuid>:<datasource>"; values[] aligns to legend[].
	sid := rawLogin(url, user, password)
	start := time.Now().Unix() - 300
	req, _ := http.NewRequest("GET", fmt.Sprintf("%s/rrd_updates?session_id=%s&host=true&start=%d", url, sid, start), nil)
	req.Header.Set("accept", "application/json")
	resp, err := insecureClient().Do(req)
	check(err)
	defer resp.Body.Close()

	var rrd struct {
		Meta struct {
			Legend []string `json:"legend"`
		} `json:"meta"`
		Data []struct {
			Values []any `json:"values"`
		} `json:"data"`
	}
	check(json.NewDecoder(resp.Body).Decode(&rrd))

	peak := map[string]float64{}
	for _, point := range rrd.Data {
		for k, legend := range rrd.Meta.Legend {
			parts := strings.Split(legend, ":")
			if parts[1] != "host" || parts[3] != "pvsaccelerator_space_utilization" {
				continue
			}
			// A host sends each value as a string ("0.0", or "NaN" for a gap in the series).
			var v float64
			switch x := point.Values[k].(type) {
			case string:
				v, _ = strconv.ParseFloat(x, 64)
			case float64:
				v = x
			}
			if v != v { // NaN: a gap in the series, not a real sample - never let it stick
				continue
			}
			// A plain `v > peak[key]` relies on a zero-valued map default, so a real 0.0 reading
			// (the common, unconfigured-PVS case) would never get inserted and the whole per-host
			// loop would silently print nothing - track presence explicitly instead.
			if cur, ok := peak[parts[2]]; !ok || v > cur {
				peak[parts[2]] = v
			}
		}
	}
	for uuid, p := range peak {
		fmt.Printf("  %s: peak PVS cache utilisation %.0f%%\n", nameByUUID[uuid], p)
	}
	fmt.Println("OK: rrd-metrics")
}
```

<details><summary>Example output</summary>

```text
  sdk-host1: peak PVS cache utilisation 94%
OK: rrd-metrics
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-RrdMetrics.ps1`](../../powershell/HostsAndPools/Invoke-RrdMetrics.ps1)

```powershell
function Invoke-RrdMetrics {
    <#
    .SYNOPSIS
        Read RRD performance metrics.
    .DESCRIPTION
        Pull recent host performance samples from the RRD archives over the performance-data HTTP API, parse
        the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space utilisation
        per host).
    .EXAMPLE
        Invoke-RrdMetrics -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # The module ships no RRD cmdlet, so read the last 5 minutes of samples from the rrd_updates HTTP API
    # (the module already trusts the server cert). Legends look like "AVERAGE:host:<uuid>:<datasource>".
    $start = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 300
    $resp = Invoke-RestMethod -Uri "$($session.Url)/rrd_updates?session_id=$($session.opaque_ref)&host=true&start=$start" `
        -Headers @{ accept = 'application/json' }
    $legends = @($resp.meta.legend)

    $peak = @{}
    foreach ($point in $resp.data) {
        for ($k = 0; $k -lt $legends.Count; $k++) {
            $parts = $legends[$k] -split ':'
            if ($parts[1] -eq 'host' -and $parts[3] -eq 'pvsaccelerator_space_utilization') {
                $u = [double]$point.values[$k]
                # NaN: a gap in the series, not a real sample - never let it stick.
                if ([double]::IsNaN($u)) { continue }
                if (-not $peak.ContainsKey($parts[2]) -or $u -gt $peak[$parts[2]]) { $peak[$parts[2]] = $u }
            }
        }
    }
    foreach ($xenHost in Get-XenHost) {
        if ($peak.ContainsKey($xenHost.uuid)) {
            Write-Host ("  {0}: peak PVS cache utilisation {1:N0}%" -f $xenHost.name_label, $peak[$xenHost.uuid])
        }
    }
    Write-Host "OK: rrd-metrics"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
  sdk-host1: peak PVS cache utilisation 94%
OK: rrd-metrics
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/rrd-metrics.sh`](../../cli/hosts-and-pools/rrd-metrics.sh)

```bash
# Read RRD performance metrics.
#
# Pull recent host performance samples from the RRD archives over the performance-data HTTP API, parse the
# legends and data, and summarise a metric (here the peak PVS Accelerator cache-space utilisation per host).
#
# Run it:
#   ./workflows.sh rrd-metrics https://xenserver root "$password"

rrd_metrics() {
    # xe host-data-source-query reads a live data source straight from the host's RRDs.
    hosts=$(xe host-list --minimal)
    for h in ${hosts//,/ }; do
        name=$(xe host-param-get uuid=$h param-name=name-label)
        util=$(xe host-data-source-query uuid=$h data-source=pvsaccelerator_space_utilization)
        echo "  $name: current PVS cache utilisation ${util%.*}%"
    done
    echo "OK: rrd-metrics"
}
```

<details><summary>Example output</summary>

```text
  sdk-host1: current PVS cache utilisation 94%
  sdk-host2: current PVS cache utilisation 78%
OK: rrd-metrics
```

</details>
