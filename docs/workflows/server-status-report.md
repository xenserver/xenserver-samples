<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Collect a server status report

Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the whole bundle, then download a smaller one covering only the sections you pick.

Workflow `server-status-report`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/ServerStatusReport.cs`](../../csharp/HostsAndPools/ServerStatusReport.cs)

```csharp
/// <summary>
/// Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the whole
/// bundle, then download a smaller one covering only the sections you pick.
/// </summary>
public static void ServerStatusReport(string url, string user, string password)
{
    var session = Connect(url, user, password);

    // Report on the coordinator. Each host answers for itself, so which one you ask decides whose
    // logs you get — support normally wants every host, one download each.
    var host = Pool.get_master(session, Pool.get_all(session).First().opaque_ref).opaque_ref;
    Console.WriteLine($"Status report for {Host.get_name_label(session, host)}");

    // The host publishes a catalogue of the sections it can report on, each with a size estimate and
    // whether it may contain personal data, so a client can offer an informed choice rather than
    // hard-coding the list.
    var keys = new List<string>();
    var defaults = new List<string>();
    foreach (var capability in XDocument.Parse(
                 Host.get_system_status_capabilities(session, host)).Root!.Elements())
    {
        var key = (string)capability.Attribute("key")!;
        keys.Add(key);
        if ((string)capability.Attribute("default-checked")! == "yes") defaults.Add(key);
        Console.WriteLine($"  {key,-22} "
                          + $"max {(string)capability.Attribute("max-size")!,9} bytes  "
                          + $"default={(string)capability.Attribute("default-checked")!,-3} "
                          + $"pii={(string)capability.Attribute("pii")!}");
    }

    // Take the sections the host marks default-checked: asking for every section can mean gigabytes (VM
    // memory dumps, every log) and a long wait while the host builds it.
    var whole = FetchStatusReport(session, url, defaults);
    Console.WriteLine($"default sections ({defaults.Count} of {keys.Count}): {whole} bytes");

    // Pick a real, small section from the host's own catalogue rather than assuming a name: the
    // catalogue is server-defined (xen-bugtool's own --capabilities output), not a fixed client
    // list, and "xenserver-config" isn't one of the real keys any host actually publishes.
    var subsetKey = keys.FirstOrDefault(k => k is "firstboot" or "network-status") ?? keys[0];
    var subset = FetchStatusReport(session, url, new[] { subsetKey });
    Console.WriteLine($"{subsetKey} only:   {subset} bytes");
    if (subset >= whole)
        Console.WriteLine("  ERROR: selecting fewer sections did not produce a smaller bundle");

    Console.WriteLine("OK: server-status-report");
    session.logout();
}

/// <summary>
/// Download the bundle for the given capability keys (a tar archive) to a temp file, streaming it - a
/// report can be large - and return its size. This example then deletes it; you'd keep it.
/// </summary>
private static long FetchStatusReport(Session session, string url, IEnumerable<string> entries)
{
    var path = Path.Combine(Path.GetTempPath(), $"sdk-example-status-{Guid.NewGuid():N}.tar");
    try
    {
        using var client = InsecureHttpClient();
        // A full report (all sections) can take well over the default 5-minute client timeout on a
        // real host with a lot to report on; this download alone gets a much longer allowance.
        client.Timeout = TimeSpan.FromMinutes(30);
        using var response = client.GetAsync(
            $"{url}/system-status?session_id={session.opaque_ref}&output=tar"
            + $"&entries={string.Join(",", entries)}",
            HttpCompletionOption.ResponseHeadersRead).Result;
        response.EnsureSuccessStatusCode();
        using (var httpStream = response.Content.ReadAsStreamAsync().Result)
        using (var fileStream = File.Create(path))
            httpStream.CopyTo(fileStream);
        return new FileInfo(path).Length;
    }
    finally
    {
        File.Delete(path);
    }
}
```

<details><summary>Example output</summary>

```text
Status report for sdk-host1
  blobs                  max   5242880 bytes  default=yes pii=no
  boot-loader            max      3072 bytes  default=yes pii=no
  device-model           max   8388608 bytes  default=yes pii=yes
  disk-info              max   8388608 bytes  default=yes pii=maybe
  fcoe                   max         0 bytes  default=yes pii=yes
  firstboot              max     81920 bytes  default=yes pii=yes
  hardware-info          max    819200 bytes  default=yes pii=maybe
  high-availability      max   5242880 bytes  default=yes pii=maybe
  host-crashdump-logs    max         0 bytes  default=yes pii=maybe
  kernel-info            max    368640 bytes  default=yes pii=maybe
  loopback-devices       max      1024 bytes  default=yes pii=maybe
  multipath              max     20480 bytes  default=yes pii=maybe
  network-config         max  10485760 bytes  default=yes pii=if_customized
  network-status         max         0 bytes  default=yes pii=yes
  pam                    max  52428800 bytes  default=yes pii=yes
  process-list           max     30720 bytes  default=yes pii=yes
  system-load            max  73400320 bytes  default=yes pii=maybe
  system-logs            max  52428800 bytes  default=yes pii=maybe
  system-services        max    131072 bytes  default=yes pii=no
  tapdisk-logs           max  10485760 bytes  default=yes pii=no
  vtpm                   max      5120 bytes  default=yes pii=no
  xapi-debug             max         0 bytes  default=yes pii=maybe
  xapi-subprocess        max      5120 bytes  default=yes pii=no
  xen-bugtool            max        -1 bytes  default=yes pii=no
  xenserver-config       max    163840 bytes  default=yes pii=maybe
  xenserver-domains      max      1024 bytes  default=yes pii=no
  xenserver-databases    max  12582912 bytes  default=yes pii=yes
  xenserver-install      max   4194304 bytes  default=yes pii=maybe
  xenserver-logs         max  73400320 bytes  default=yes pii=maybe
  xen-info               max     20480 bytes  default=yes pii=maybe
  xha-liveset            max     10240 bytes  default=yes pii=maybe
  yum                    max    102400 bytes  default=yes pii=if_customized
  cron                   max    102400 bytes  default=yes pii=if_customized
  block-scheduler        max    102400 bytes  default=yes pii=no
  gfs2                   max  10485760 bytes  default=yes pii=no
  lstopo                 max     65536 bytes  default=yes pii=maybe
  observer               max 104857600 bytes  default=yes pii=maybe
  xspvscache             max     16384 bytes  default=yes pii=maybe
  message-switch         max     16384 bytes  default=yes pii=maybe
  VM-snapshot-schedule   max  10485760 bytes  default=yes pii=no
  control-slice          max     16384 bytes  default=yes pii=maybe
  xenopsd                max   1638400 bytes  default=yes pii=maybe
  xapi-clusterd          max   1638400 bytes  default=yes pii=maybe
  xapi                   max     16384 bytes  default=yes pii=yes
  xcp-rrdd-plugins       max  13107200 bytes  default=yes pii=maybe
  v6d                    max   1638400 bytes  default=yes pii=maybe
default sections (46 of 46): 11264 bytes
firstboot only:   2048 bytes
OK: server-status-report
```

</details>

## Python

Source: [`python/hosts_and_pools/server_status_report.py`](../../python/hosts_and_pools/server_status_report.py)

```python
"""Collect a server status report.

Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the
whole bundle, then download a smaller one covering only the sections you pick.
"""

import os
import shutil
import ssl
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

from connection import connect


def server_status_report(url, username, password):
    """Gather a host's diagnostic bundle -- the archive support asks for.

    The host publishes a catalogue of the sections it can report on, each with a size
    estimate and whether it may contain personal data, so a client can offer an informed
    choice rather than hard-coding the list. The bundle itself is an HTTP download
    alongside the API, and the chosen sections travel in the query string."""
    session = connect(url, username, password)
    x = session.xenapi
    ctx = ssl._create_unverified_context()

    # Report on the coordinator. Each host answers for itself, so which one you ask decides
    # whose logs you get -- support normally wants every host, one download each.
    host = x.pool.get_master(x.pool.get_all()[0])
    print("Status report for %s" % x.host.get_name_label(host))

    keys, defaults = [], []
    for capability in ET.fromstring(x.host.get_system_status_capabilities(host)):
        keys.append(capability.get("key"))
        if capability.get("default-checked") == "yes":
            defaults.append(capability.get("key"))
        print("  %-22s max %9s bytes  default=%-3s pii=%s"
              % (capability.get("key"), capability.get("max-size"),
                 capability.get("default-checked"), capability.get("pii")))

    # Take the sections the host marks default-checked: asking for every section can mean gigabytes (VM
    # memory dumps, every log) and a long wait while the host builds it.
    whole = fetch_status_report(url, session, ctx, defaults)
    print("default sections (%d of %d): %d bytes" % (len(defaults), len(keys), whole))

    # Pick a real, small section from the host's own catalogue rather than assuming a name: the
    # catalogue is server-defined (xen-bugtool's own --capabilities output), not a fixed client
    # list, and "xenserver-config" isn't one of the real keys any host actually publishes.
    subset_key = next((k for k in keys if k in ("firstboot", "network-status")), keys[0])
    subset = fetch_status_report(url, session, ctx, [subset_key])
    print("%s only:   %d bytes" % (subset_key, subset))
    if subset >= whole:
        print("  ERROR: selecting fewer sections did not produce a smaller bundle")

    print("OK: server-status-report")
    session.logout()


def fetch_status_report(url, session, ctx, entries):
    """Download the bundle for the given capability keys (a tar archive) to a file, streaming it -
    a report can be large - and return its size. This example then deletes it; you'd keep it."""
    request = "%s/system-status?session_id=%s&output=tar&entries=%s" \
              % (url, session._session, ",".join(entries))
    handle, path = tempfile.mkstemp(prefix="sdk-example-status-", suffix=".tar")
    try:
        with os.fdopen(handle, "wb") as out, urllib.request.urlopen(request, context=ctx) as response:
            shutil.copyfileobj(response, out, 1024 * 1024)
        return os.path.getsize(path)
    finally:
        os.remove(path)
```

<details><summary>Example output</summary>

```text
Status report for sdk-host1
  blobs                  max   5242880 bytes  default=yes pii=no
  boot-loader            max      3072 bytes  default=yes pii=no
  device-model           max   8388608 bytes  default=yes pii=yes
  disk-info              max   8388608 bytes  default=yes pii=maybe
  fcoe                   max         0 bytes  default=yes pii=yes
  firstboot              max     81920 bytes  default=yes pii=yes
  hardware-info          max    819200 bytes  default=yes pii=maybe
  high-availability      max   5242880 bytes  default=yes pii=maybe
  host-crashdump-logs    max         0 bytes  default=yes pii=maybe
  kernel-info            max    368640 bytes  default=yes pii=maybe
  loopback-devices       max      1024 bytes  default=yes pii=maybe
  multipath              max     20480 bytes  default=yes pii=maybe
  network-config         max  10485760 bytes  default=yes pii=if_customized
  network-status         max         0 bytes  default=yes pii=yes
  pam                    max  52428800 bytes  default=yes pii=yes
  process-list           max     30720 bytes  default=yes pii=yes
  system-load            max  73400320 bytes  default=yes pii=maybe
  system-logs            max  52428800 bytes  default=yes pii=maybe
  system-services        max    131072 bytes  default=yes pii=no
  tapdisk-logs           max  10485760 bytes  default=yes pii=no
  vtpm                   max      5120 bytes  default=yes pii=no
  xapi-debug             max         0 bytes  default=yes pii=maybe
  xapi-subprocess        max      5120 bytes  default=yes pii=no
  xen-bugtool            max        -1 bytes  default=yes pii=no
  xenserver-config       max    163840 bytes  default=yes pii=maybe
  xenserver-domains      max      1024 bytes  default=yes pii=no
  xenserver-databases    max  12582912 bytes  default=yes pii=yes
  xenserver-install      max   4194304 bytes  default=yes pii=maybe
  xenserver-logs         max  73400320 bytes  default=yes pii=maybe
  xen-info               max     20480 bytes  default=yes pii=maybe
  xha-liveset            max     10240 bytes  default=yes pii=maybe
  yum                    max    102400 bytes  default=yes pii=if_customized
  cron                   max    102400 bytes  default=yes pii=if_customized
  block-scheduler        max    102400 bytes  default=yes pii=no
  gfs2                   max  10485760 bytes  default=yes pii=no
  lstopo                 max     65536 bytes  default=yes pii=maybe
  observer               max 104857600 bytes  default=yes pii=maybe
  xspvscache             max     16384 bytes  default=yes pii=maybe
  message-switch         max     16384 bytes  default=yes pii=maybe
  VM-snapshot-schedule   max  10485760 bytes  default=yes pii=no
  control-slice          max     16384 bytes  default=yes pii=maybe
  xenopsd                max   1638400 bytes  default=yes pii=maybe
  xapi-clusterd          max   1638400 bytes  default=yes pii=maybe
  xapi                   max     16384 bytes  default=yes pii=yes
  xcp-rrdd-plugins       max  13107200 bytes  default=yes pii=maybe
  v6d                    max   1638400 bytes  default=yes pii=maybe
default sections (46 of 46): 11264 bytes
firstboot only:   2048 bytes
OK: server-status-report
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ServerStatusReport.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ServerStatusReport.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;

import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class ServerStatusReport {
    private ServerStatusReport() {
    }

    /**
     * Collect a server status report.
     *
     * <p>Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the
     * whole bundle, then download a smaller one covering only the sections you pick.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Report on the coordinator. Each host answers for itself, so which one you ask decides
            // whose logs you get - support normally wants every host, one download each.
            Host host = Pool.getAll(conn).iterator().next().getMaster(conn);
            System.out.println("Status report for " + host.getNameLabel(conn));

            // The host publishes a catalogue of the sections it can report on, each with a size
            // estimate and whether it may contain personal data, so a client can offer an informed
            // choice rather than hard-coding the list.
            org.w3c.dom.NodeList capabilities = javax.xml.parsers.DocumentBuilderFactory.newInstance()
                .newDocumentBuilder()
                .parse(new org.xml.sax.InputSource(new java.io.StringReader(
                    host.getSystemStatusCapabilities(conn))))
                .getElementsByTagName("capability");
            java.util.List<String> keys = new java.util.ArrayList<>();
            java.util.List<String> defaults = new java.util.ArrayList<>();
            for (int i = 0; i < capabilities.getLength(); i++) {
                org.w3c.dom.Element capability = (org.w3c.dom.Element) capabilities.item(i);
                String key = capability.getAttribute("key");
                keys.add(key);
                if ("yes".equals(capability.getAttribute("default-checked"))) defaults.add(key);
                System.out.printf("  %-22s max %9s bytes  default=%-3s pii=%s%n",
                    key, capability.getAttribute("max-size"),
                    capability.getAttribute("default-checked"), capability.getAttribute("pii"));
            }

            // The download is an HTTP transfer alongside the API, so the session id travels in the
            // query string.
            String session = conn.getSessionReference();
            // Take the sections the host marks default-checked: asking for every section can mean
            // gigabytes (VM memory dumps, every log) and a long wait while the host builds it.
            long whole = fetchStatusReport(url, session, defaults);
            System.out.printf("default sections (%d of %d): %d bytes%n", defaults.size(), keys.size(), whole);

            // Pick a real, small section from the host's own catalogue rather than assuming a name: the
            // catalogue is server-defined (xen-bugtool's own --capabilities output), not a fixed client
            // list, and "xenserver-config" isn't one of the real keys any host actually publishes.
            String subsetKey = keys.get(0);
            for (String k : keys) {
                if (k.equals("firstboot") || k.equals("network-status")) { subsetKey = k; break; }
            }
            long subset = fetchStatusReport(url, session, java.util.Arrays.asList(subsetKey));
            System.out.printf("%s only:   %d bytes%n", subsetKey, subset);
            if (subset >= whole)
                System.out.println("  ERROR: selecting fewer sections did not produce a smaller bundle");

            System.out.println("OK: server-status-report");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Downloads the bundle for the given capability keys (a tar archive) to a temp file, streaming it - a
     * report can be large - and returns its size. This example then deletes it; you'd keep it.
     */
    private static long fetchStatusReport(String url, String session,
                                          java.util.List<String> entries) throws Exception {
        java.io.File file = java.io.File.createTempFile("sdk-example-status-", ".tar");
        try {
            HttpGet get = new HttpGet(url + "/system-status?session_id=" + session + "&output=tar"
                + "&entries=" + String.join(",", entries));
            try (CloseableHttpClient http = trustingHttpClient()) {
                http.execute(get, resp -> {
                    try (java.io.InputStream in = resp.getEntity().getContent()) {
                        java.nio.file.Files.copy(in, file.toPath(),
                            java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    }
                    return null;
                });
            }
            return file.length();
        } finally {
            file.delete();
        }
    }
}
```

<details><summary>Example output</summary>

```text
Status report for sdk-host1
  blobs                  max   5242880 bytes  default=yes pii=no
  boot-loader            max      3072 bytes  default=yes pii=no
  device-model           max   8388608 bytes  default=yes pii=yes
  disk-info              max   8388608 bytes  default=yes pii=maybe
  fcoe                   max         0 bytes  default=yes pii=yes
  firstboot              max     81920 bytes  default=yes pii=yes
  hardware-info          max    819200 bytes  default=yes pii=maybe
  high-availability      max   5242880 bytes  default=yes pii=maybe
  host-crashdump-logs    max         0 bytes  default=yes pii=maybe
  kernel-info            max    368640 bytes  default=yes pii=maybe
  loopback-devices       max      1024 bytes  default=yes pii=maybe
  multipath              max     20480 bytes  default=yes pii=maybe
  network-config         max  10485760 bytes  default=yes pii=if_customized
  network-status         max         0 bytes  default=yes pii=yes
  pam                    max  52428800 bytes  default=yes pii=yes
  process-list           max     30720 bytes  default=yes pii=yes
  system-load            max  73400320 bytes  default=yes pii=maybe
  system-logs            max  52428800 bytes  default=yes pii=maybe
  system-services        max    131072 bytes  default=yes pii=no
  tapdisk-logs           max  10485760 bytes  default=yes pii=no
  vtpm                   max      5120 bytes  default=yes pii=no
  xapi-debug             max         0 bytes  default=yes pii=maybe
  xapi-subprocess        max      5120 bytes  default=yes pii=no
  xen-bugtool            max        -1 bytes  default=yes pii=no
  xenserver-config       max    163840 bytes  default=yes pii=maybe
  xenserver-domains      max      1024 bytes  default=yes pii=no
  xenserver-databases    max  12582912 bytes  default=yes pii=yes
  xenserver-install      max   4194304 bytes  default=yes pii=maybe
  xenserver-logs         max  73400320 bytes  default=yes pii=maybe
  xen-info               max     20480 bytes  default=yes pii=maybe
  xha-liveset            max     10240 bytes  default=yes pii=maybe
  yum                    max    102400 bytes  default=yes pii=if_customized
  cron                   max    102400 bytes  default=yes pii=if_customized
  block-scheduler        max    102400 bytes  default=yes pii=no
  gfs2                   max  10485760 bytes  default=yes pii=no
  lstopo                 max     65536 bytes  default=yes pii=maybe
  observer               max 104857600 bytes  default=yes pii=maybe
  xspvscache             max     16384 bytes  default=yes pii=maybe
  message-switch         max     16384 bytes  default=yes pii=maybe
  VM-snapshot-schedule   max  10485760 bytes  default=yes pii=no
  control-slice          max     16384 bytes  default=yes pii=maybe
  xenopsd                max   1638400 bytes  default=yes pii=maybe
  xapi-clusterd          max   1638400 bytes  default=yes pii=maybe
  xapi                   max     16384 bytes  default=yes pii=yes
  xcp-rrdd-plugins       max  13107200 bytes  default=yes pii=maybe
  v6d                    max   1638400 bytes  default=yes pii=maybe
default sections (46 of 46): 11264 bytes
firstboot only:   2048 bytes
OK: server-status-report
```

</details>

## Go

Source: [`go/server_status_report.go`](../../go/server_status_report.go)

```go
package main

import (
	"encoding/xml"
	"fmt"
	"io"
	"os"
	"strings"

	"go/xenapi"
)

// serverStatusReport - Collect a server status report.
//
// Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the
// whole bundle, then download a smaller one covering only the sections you pick.
func serverStatusReport(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	// Report on the coordinator. Each host answers for itself, so which one you ask decides whose logs
	// you get - support normally wants every host, one download each.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	name, err := xenapi.Host.GetNameLabel(session, host)
	check(err)
	fmt.Printf("Status report for %s\n", name)

	// The host publishes a catalogue of the sections it can report on, each with a size estimate and
	// whether it may contain personal data, so a client can offer an informed choice rather than
	// hard-coding the list.
	capabilitiesXML, err := xenapi.Host.GetSystemStatusCapabilities(session, host)
	check(err)
	var catalogue struct {
		Capabilities []struct {
			Key            string `xml:"key,attr"`
			MaxSize        string `xml:"max-size,attr"`
			DefaultChecked string `xml:"default-checked,attr"`
			Pii            string `xml:"pii,attr"`
		} `xml:"capability"`
	}
	check(xml.Unmarshal([]byte(capabilitiesXML), &catalogue))
	var keys, defaults []string
	for _, capability := range catalogue.Capabilities {
		keys = append(keys, capability.Key)
		if capability.DefaultChecked == "yes" {
			defaults = append(defaults, capability.Key)
		}
		fmt.Printf("  %-22s max %9s bytes  default=%-3s pii=%s\n",
			capability.Key, capability.MaxSize, capability.DefaultChecked, capability.Pii)
	}

	// The download is an HTTP transfer alongside the API, so the session id travels in the query string.
	// The Go binding keeps its own session private, so obtain one of our own.
	sid := rawLogin(url, user, password)
	// Take the sections the host marks default-checked: asking for every section can mean gigabytes (VM
	// memory dumps, every log) and a long wait while the host builds it.
	whole := fetchStatusReport(url, sid, defaults)
	fmt.Printf("default sections (%d of %d): %d bytes\n", len(defaults), len(keys), whole)

	// Pick a real, small section from the host's own catalogue rather than assuming a name: the
	// catalogue is server-defined (xen-bugtool's own --capabilities output), not a fixed client
	// list, and "xenserver-config" isn't one of the real keys any host actually publishes.
	subsetKey := keys[0]
	for _, k := range keys {
		if k == "firstboot" || k == "network-status" {
			subsetKey = k
			break
		}
	}
	subset := fetchStatusReport(url, sid, []string{subsetKey})
	fmt.Printf("%s only:   %d bytes\n", subsetKey, subset)
	if subset >= whole {
		fmt.Println("  ERROR: selecting fewer sections did not produce a smaller bundle")
	}

	fmt.Println("OK: server-status-report")
}

// fetchStatusReport downloads the bundle for the given capability keys (a tar archive) to a temp file,
// streaming it - a report can be large - and returns its size. This example then deletes it; you'd keep it.
func fetchStatusReport(url, sid string, entries []string) int {
	resp, err := insecureClient().Get(fmt.Sprintf("%s/system-status?session_id=%s&output=tar&entries=%s",
		url, sid, strings.Join(entries, ",")))
	check(err)
	defer resp.Body.Close()

	temp, err := os.CreateTemp("", "sdk-example-status-*.tar")
	check(err)
	path := temp.Name()
	defer os.Remove(path)

	written, err := io.Copy(temp, resp.Body)
	check(err)
	temp.Close()
	return int(written)
}
```

<details><summary>Example output</summary>

```text
Status report for sdk-host1
  blobs                  max   5242880 bytes  default=yes pii=no
  boot-loader            max      3072 bytes  default=yes pii=no
  device-model           max   8388608 bytes  default=yes pii=yes
  disk-info              max   8388608 bytes  default=yes pii=maybe
  fcoe                   max         0 bytes  default=yes pii=yes
  firstboot              max     81920 bytes  default=yes pii=yes
  hardware-info          max    819200 bytes  default=yes pii=maybe
  high-availability      max   5242880 bytes  default=yes pii=maybe
  host-crashdump-logs    max         0 bytes  default=yes pii=maybe
  kernel-info            max    368640 bytes  default=yes pii=maybe
  loopback-devices       max      1024 bytes  default=yes pii=maybe
  multipath              max     20480 bytes  default=yes pii=maybe
  network-config         max  10485760 bytes  default=yes pii=if_customized
  network-status         max         0 bytes  default=yes pii=yes
  pam                    max  52428800 bytes  default=yes pii=yes
  process-list           max     30720 bytes  default=yes pii=yes
  system-load            max  73400320 bytes  default=yes pii=maybe
  system-logs            max  52428800 bytes  default=yes pii=maybe
  system-services        max    131072 bytes  default=yes pii=no
  tapdisk-logs           max  10485760 bytes  default=yes pii=no
  vtpm                   max      5120 bytes  default=yes pii=no
  xapi-debug             max         0 bytes  default=yes pii=maybe
  xapi-subprocess        max      5120 bytes  default=yes pii=no
  xen-bugtool            max        -1 bytes  default=yes pii=no
  xenserver-config       max    163840 bytes  default=yes pii=maybe
  xenserver-domains      max      1024 bytes  default=yes pii=no
  xenserver-databases    max  12582912 bytes  default=yes pii=yes
  xenserver-install      max   4194304 bytes  default=yes pii=maybe
  xenserver-logs         max  73400320 bytes  default=yes pii=maybe
  xen-info               max     20480 bytes  default=yes pii=maybe
  xha-liveset            max     10240 bytes  default=yes pii=maybe
  yum                    max    102400 bytes  default=yes pii=if_customized
  cron                   max    102400 bytes  default=yes pii=if_customized
  block-scheduler        max    102400 bytes  default=yes pii=no
  gfs2                   max  10485760 bytes  default=yes pii=no
  lstopo                 max     65536 bytes  default=yes pii=maybe
  observer               max 104857600 bytes  default=yes pii=maybe
  xspvscache             max     16384 bytes  default=yes pii=maybe
  message-switch         max     16384 bytes  default=yes pii=maybe
  VM-snapshot-schedule   max  10485760 bytes  default=yes pii=no
  control-slice          max     16384 bytes  default=yes pii=maybe
  xenopsd                max   1638400 bytes  default=yes pii=maybe
  xapi-clusterd          max   1638400 bytes  default=yes pii=maybe
  xapi                   max     16384 bytes  default=yes pii=yes
  xcp-rrdd-plugins       max  13107200 bytes  default=yes pii=maybe
  v6d                    max   1638400 bytes  default=yes pii=maybe
default sections (46 of 46): 11264 bytes
firstboot only:   2048 bytes
OK: server-status-report
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ServerStatusReport.ps1`](../../powershell/HostsAndPools/Invoke-ServerStatusReport.ps1)

```powershell
function Invoke-ServerStatusReport {
    <#
    .SYNOPSIS
        Collect a server status report.
    .DESCRIPTION
        Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the
        whole bundle, then download a smaller one covering only the sections you pick.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # Report on the coordinator. Each host answers for itself, so which one you ask decides whose logs
    # you get - support normally wants every host, one download each.
    $pool = Get-XenPool | Select-Object -First 1
    $xenHost = Get-XenHost -Ref $pool.master.opaque_ref
    Write-Host "Status report for $($xenHost.name_label)"

    # The host publishes a catalogue of the sections it can report on, each with a size estimate and
    # whether it may contain personal data, so a client can offer an informed choice rather than
    # hard-coding the list.
    # A read, so it is a property rather than an action: Invoke-XenHost's -XenAction set covers the
    # host's verbs, and this is not one of them.
    $catalogue = [xml](Get-XenHostProperty -XenHost $xenHost -XenProperty SystemStatusCapabilities)
    $keys = @()
    $defaults = @()
    foreach ($capability in $catalogue.'system-status-capabilities'.capability) {
        $keys += $capability.key
        if ($capability.'default-checked' -eq 'yes') { $defaults += $capability.key }
        Write-Host ("  {0,-22} max {1,9} bytes  default={2,-3} pii={3}" -f
            $capability.key, $capability.'max-size', $capability.'default-checked', $capability.pii)
    }

    # The download is an HTTP transfer alongside the API, so the session id travels in the query string.
    # Still pure PowerShell: Connect-Example has already trusted the server's certificate. Take the
    # sections the host marks default-checked: asking for every section can mean gigabytes (VM memory
    # dumps, every log) and a long wait while the host builds it.
    $whole = Get-StatusReportSize -Url $Url -Session $session -Entries $defaults
    Write-Host ("default sections ({0} of {1}): {2} bytes" -f $defaults.Count, $keys.Count, $whole)

    # Pick a real, small section from the host's own catalogue rather than assuming a name: the
    # catalogue is server-defined (xen-bugtool's own --capabilities output), not a fixed client list,
    # and "xenserver-config" isn't one of the real keys any host actually publishes.
    $subsetKey = $keys | Where-Object { $_ -in @("firstboot", "network-status") } | Select-Object -First 1
    if (-not $subsetKey) { $subsetKey = $keys[0] }
    $subset = Get-StatusReportSize -Url $Url -Session $session -Entries @($subsetKey)
    Write-Host ("{0} only:   {1} bytes" -f $subsetKey, $subset)
    if ($subset -ge $whole) {
        Write-Host "  ERROR: selecting fewer sections did not produce a smaller bundle"
    }

    Write-Host "OK: server-status-report"
    $session | Disconnect-XenServer
}

function Get-StatusReportSize {
    <#
    .SYNOPSIS
        Downloads the bundle for the given capability keys (a tar archive) to a temp file, streaming it - a
        report can be large - and returns its size.
    .DESCRIPTION
        This example then deletes it; you'd keep it.
    #>
    param([string]$Url, $Session, [string[]]$Entries)
    $path = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-status-$([guid]::NewGuid().Guid).tar"
    try {
        Invoke-WebRequest -UseBasicParsing -OutFile $path `
            -Uri ("$Url/system-status?session_id=$($Session.opaque_ref)&output=tar" +
                  "&entries=$($Entries -join ',')")
        (Get-Item $path).Length
    }
    finally {
        Remove-Item $path -ErrorAction SilentlyContinue
    }
}
```

<details><summary>Example output</summary>

```text
Status report for sdk-host1
  blobs                  max   5242880 bytes  default=yes pii=no
  boot-loader            max      3072 bytes  default=yes pii=no
  device-model           max   8388608 bytes  default=yes pii=yes
  disk-info              max   8388608 bytes  default=yes pii=maybe
  fcoe                   max         0 bytes  default=yes pii=yes
  firstboot              max     81920 bytes  default=yes pii=yes
  hardware-info          max    819200 bytes  default=yes pii=maybe
  high-availability      max   5242880 bytes  default=yes pii=maybe
  host-crashdump-logs    max         0 bytes  default=yes pii=maybe
  kernel-info            max    368640 bytes  default=yes pii=maybe
  loopback-devices       max      1024 bytes  default=yes pii=maybe
  multipath              max     20480 bytes  default=yes pii=maybe
  network-config         max  10485760 bytes  default=yes pii=if_customized
  network-status         max         0 bytes  default=yes pii=yes
  pam                    max  52428800 bytes  default=yes pii=yes
  process-list           max     30720 bytes  default=yes pii=yes
  system-load            max  73400320 bytes  default=yes pii=maybe
  system-logs            max  52428800 bytes  default=yes pii=maybe
  system-services        max    131072 bytes  default=yes pii=no
  tapdisk-logs           max  10485760 bytes  default=yes pii=no
  vtpm                   max      5120 bytes  default=yes pii=no
  xapi-debug             max         0 bytes  default=yes pii=maybe
  xapi-subprocess        max      5120 bytes  default=yes pii=no
  xen-bugtool            max        -1 bytes  default=yes pii=no
  xenserver-config       max    163840 bytes  default=yes pii=maybe
  xenserver-domains      max      1024 bytes  default=yes pii=no
  xenserver-databases    max  12582912 bytes  default=yes pii=yes
  xenserver-install      max   4194304 bytes  default=yes pii=maybe
  xenserver-logs         max  73400320 bytes  default=yes pii=maybe
  xen-info               max     20480 bytes  default=yes pii=maybe
  xha-liveset            max     10240 bytes  default=yes pii=maybe
  yum                    max    102400 bytes  default=yes pii=if_customized
  cron                   max    102400 bytes  default=yes pii=if_customized
  block-scheduler        max    102400 bytes  default=yes pii=no
  gfs2                   max  10485760 bytes  default=yes pii=no
  lstopo                 max     65536 bytes  default=yes pii=maybe
  observer               max 104857600 bytes  default=yes pii=maybe
  xspvscache             max     16384 bytes  default=yes pii=maybe
  message-switch         max     16384 bytes  default=yes pii=maybe
  VM-snapshot-schedule   max  10485760 bytes  default=yes pii=no
  control-slice          max     16384 bytes  default=yes pii=maybe
  xenopsd                max   1638400 bytes  default=yes pii=maybe
  xapi-clusterd          max   1638400 bytes  default=yes pii=maybe
  xapi                   max     16384 bytes  default=yes pii=yes
  xcp-rrdd-plugins       max  13107200 bytes  default=yes pii=maybe
  v6d                    max   1638400 bytes  default=yes pii=maybe
default sections (46 of 46): 11264 bytes
firstboot only:   2048 bytes
OK: server-status-report
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/server-status-report.sh`](../../cli/hosts-and-pools/server-status-report.sh)

```bash
# Collect a server status report.
#
# Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the whole
# bundle, then download a smaller one covering only the sections you pick.
#
# Run it:
#   ./workflows.sh server-status-report https://xenserver root "$password"

server_status_report() {
    # Each host answers for itself, so which one you ask decides whose logs you get - support normally
    # wants one report per host. Here, the coordinator.
    pool=$(first_csv "$(xe pool-list --minimal)")
    target=$(xe pool-param-get uuid=$pool param-name=master)
    echo "Status report for $(xe host-param-get uuid=$target param-name=name-label)"

    # The host publishes a catalogue of the sections it can report on, each with a size estimate and
    # whether it may contain personal data, so you can decide what to collect before collecting it.
    capabilities=$(xe host-get-system-status-capabilities uuid=$target)
    keys=""
    defaults=""
    # Split the XML on '<' with bash's own field splitting rather than spawning a parser: each element
    # starts a field, and the ones we want begin `capability key="..."`.
    old_ifs=$IFS; IFS='<'
    for element in $capabilities; do
        case "$element" in
            capability\ *)
                key=$(xml_attr "$element" key)
                keys="${keys:+$keys,}$key"
                default_checked=$(xml_attr "$element" default-checked)
                [ "$default_checked" = "yes" ] && defaults="${defaults:+$defaults,}$key"
                printf '  %-22s max %9s bytes  default=%-3s pii=%s\n' \
                    "$key" "$(xml_attr "$element" max-size)" \
                    "$default_checked" "$(xml_attr "$element" pii)"
                ;;
        esac
    done
    IFS=$old_ifs

    rm -f cli-status-all.tar cli-status-config.tar
    # Take the sections the host marks default-checked: asking for every section can mean gigabytes (VM
    # memory dumps, every log) and a long wait while the host builds it.
    xe host-get-system-status uuid=$target filename=cli-status-all.tar entries="$defaults"
    whole=$(stat -c %s cli-status-all.tar)
    echo "default sections ($(count_csv "$defaults") of $(count_csv "$keys")): $whole bytes"

    # Pick a real, small section from the host's own catalogue rather than assuming a name: the catalogue
    # is server-defined (xen-bugtool's own --capabilities output), not a fixed client list, and
    # "xenserver-config" isn't one of the real keys any host actually publishes.
    subset_key=""
    for preferred in firstboot network-status; do
        case ",$keys," in *",$preferred,"*) subset_key=$preferred; break ;; esac
    done
    [ -n "$subset_key" ] || subset_key=$(first_csv "$keys")

    # Worth checking rather than assuming: a server that ignored the selection would look identical from
    # here until someone opened the archive and found the whole thing.
    xe host-get-system-status uuid=$target filename=cli-status-config.tar entries="$subset_key"
    subset=$(stat -c %s cli-status-config.tar)
    echo "$subset_key only:   $subset bytes"
    if [ "$subset" -ge "$whole" ]; then
        echo "  ERROR: selecting fewer sections did not produce a smaller bundle"
    fi

    rm -f cli-status-all.tar cli-status-config.tar
    echo "OK: server-status-report"
}

# The value of a named attribute in an XML element, using parameter expansion only - no xmllint, and no
# sed/grep process per attribute. Name the attribute in full: a prefix match would make `size` collect
# `min-size` as well.
xml_attr() {
    case "$1" in
        *"$2=\""*) local rest=${1#*$2=\"}; echo "${rest%%\"*}" ;;
        *) echo "" ;;
    esac
}
```

<details><summary>Example output</summary>

```text
Status report for sdk-host1
  blobs                  max   5242880 bytes  default=yes pii=no
  boot-loader            max      3072 bytes  default=yes pii=no
  device-model           max   8388608 bytes  default=yes pii=yes
  disk-info              max   8388608 bytes  default=yes pii=maybe
  fcoe                   max         0 bytes  default=yes pii=yes
  firstboot              max     81920 bytes  default=yes pii=yes
  hardware-info          max    819200 bytes  default=yes pii=maybe
  high-availability      max   5242880 bytes  default=yes pii=maybe
  host-crashdump-logs    max         0 bytes  default=yes pii=maybe
  kernel-info            max    368640 bytes  default=yes pii=maybe
  loopback-devices       max      1024 bytes  default=yes pii=maybe
  multipath              max     20480 bytes  default=yes pii=maybe
  network-config         max  10485760 bytes  default=yes pii=if_customized
  network-status         max         0 bytes  default=yes pii=yes
  pam                    max  52428800 bytes  default=yes pii=yes
  process-list           max     30720 bytes  default=yes pii=yes
  system-load            max  73400320 bytes  default=yes pii=maybe
  system-logs            max  52428800 bytes  default=yes pii=maybe
  system-services        max    131072 bytes  default=yes pii=no
  tapdisk-logs           max  10485760 bytes  default=yes pii=no
  vtpm                   max      5120 bytes  default=yes pii=no
  xapi-debug             max         0 bytes  default=yes pii=maybe
  xapi-subprocess        max      5120 bytes  default=yes pii=no
  xen-bugtool            max        -1 bytes  default=yes pii=no
  xenserver-config       max    163840 bytes  default=yes pii=maybe
  xenserver-domains      max      1024 bytes  default=yes pii=no
  xenserver-databases    max  12582912 bytes  default=yes pii=yes
  xenserver-install      max   4194304 bytes  default=yes pii=maybe
  xenserver-logs         max  73400320 bytes  default=yes pii=maybe
  xen-info               max     20480 bytes  default=yes pii=maybe
  xha-liveset            max     10240 bytes  default=yes pii=maybe
  yum                    max    102400 bytes  default=yes pii=if_customized
  cron                   max    102400 bytes  default=yes pii=if_customized
  block-scheduler        max    102400 bytes  default=yes pii=no
  gfs2                   max  10485760 bytes  default=yes pii=no
  lstopo                 max     65536 bytes  default=yes pii=maybe
  observer               max 104857600 bytes  default=yes pii=maybe
  xspvscache             max     16384 bytes  default=yes pii=maybe
  message-switch         max     16384 bytes  default=yes pii=maybe
  VM-snapshot-schedule   max  10485760 bytes  default=yes pii=no
  control-slice          max     16384 bytes  default=yes pii=maybe
  xenopsd                max   1638400 bytes  default=yes pii=maybe
  xapi-clusterd          max   1638400 bytes  default=yes pii=maybe
  xapi                   max     16384 bytes  default=yes pii=yes
  xcp-rrdd-plugins       max  13107200 bytes  default=yes pii=maybe
  v6d                    max   1638400 bytes  default=yes pii=maybe
default sections (46 of 46): 11264 bytes
firstboot only:   2048 bytes
OK: server-status-report
```

</details>
