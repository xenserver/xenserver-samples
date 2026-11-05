<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Read workload-balancing recommendations

Point the pool at a workload-balancing appliance, read its placement recommendations for the pool and for one VM, then disconnect it.

**Requires:** a Workload Balancing appliance.

Workflow `wlb-recommendations`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/WlbRecommendations.cs`](../../csharp/HostsAndPools/WlbRecommendations.cs)

```csharp
/// <summary>
/// Point the pool at a workload-balancing appliance, read its placement recommendations for the pool and
/// for one VM, then disconnect it.
/// </summary>
/// <example>
/// <code>
/// Workflows.WlbRecommendations("https://xenserver", "root", password, "web-01",
/// Workflows.wlbHostPort: "192.0.2.60:30601", wlbUsername: "wlbuser", wlbPassword: "wlbpass",
/// Workflows.wlbCertificate: "wlb-appliance.pem");
/// </code>
/// </example>
/// <remarks>
/// <para>
/// Connect a workload-balancing appliance and read its placement advice. Needs a real, reachable WLB
/// appliance: pool.initialize_wlb makes a synchronous HTTP call to it and raises
/// WLB_CONNECTION_REFUSED/WLB_CONNECTION_RESET if it can't connect - there is no way to fake this with a
/// placeholder. wlbHostPort is host:port, with no URL scheme - that is the real wire format (xe
/// pool-initialize-wlb wlb_url="10.x.x.x:30601" ...), not a URL.
/// </para>
/// <para>
/// The pool checks the appliance's TLS certificate (pool.wlb_verify_cert), and only against the
/// certificates installed with Pool.certificate_install - not install_trusted_certificate's. A fresh
/// appliance has a self-signed one, so pass it as wlbCertificate (a PEM file): without it initialize_wlb
/// fails with INTERNAL_ERROR "Connection failed: configuration failed." and no hint that the certificate
/// is the reason.
/// </para>
/// </remarks>
public static void WlbRecommendations(string url, string user, string password, string vmName,
    string wlbHostPort = "wlb.example:8012", string wlbUsername = "wlbuser", string wlbPassword = "wlbpass",
    string wlbCertificate = "")
{
    var session = Connect(url, user, password);
    var poolRef = Pool.get_all(session)[0].opaque_ref;

    var certName = "";
    if (wlbCertificate != "")
    {
        certName = "sdk-example-wlb.pem";
        Pool.certificate_install(session, certName, File.ReadAllText(wlbCertificate)); // pool-wide: no pool argument
    }
    Pool.initialize_wlb(session, wlbHostPort, wlbUsername, wlbPassword, user, password);
    try
    {
        // Initializing connects the pool to the appliance but leaves balancing off: every WLB call
        // after this would fail WLB_DISABLED until it's switched on.
        Pool.set_wlb_enabled(session, poolRef, true);
        Console.WriteLine($"WLB: {Pool.get_wlb_url(session, poolRef)}");

        // Read BY POSITION, and the two calls do not share a shape. The pool's recommendations are
        // keyed by VM and say where to move it: [0] "wlb", [1] the destination host's UUID (a uuid,
        // not a ref), [2] and [3] ids, [4] the reason.
        foreach (var entry in Pool.retrieve_wlb_recommendations(session))
            Console.WriteLine($"  move {VM.get_name_label(session, entry.Key.opaque_ref)} " +
                              $"-> host {entry.Value[1]} ({entry.Value[4]})");

        // A VM's own recommendations are keyed by host and star-rate each as a destination:
        // [0] "wlb", [1] the rating - higher is better (a real appliance rated hosts 6.1 here, so not
        // capped at five). Right after connecting, the appliance is still discovering the pool:
        // WLB_INTERNAL_ERROR 4024 ("Pool discovery has not been started"), 4025 ("... has not been
        // completed"), then 4016 ("WLB does not have current metrics") - keep asking.
        var vm = VM.get_by_name_label(session, vmName)[0];
        var deadline = DateTime.UtcNow.AddMinutes(10);
        Dictionary<XenRef<Host>, string[]> vmRecs;
        while (true)
        {
            try
            {
                vmRecs = VM.retrieve_wlb_recommendations(session, vm.opaque_ref);
                break;
            }
            catch (Failure e)
            {
                if (e.ErrorDescription[0] != "WLB_INTERNAL_ERROR" ||
                    !new[] { "4024", "4025", "4016" }.Contains(e.ErrorDescription[1]) ||
                    DateTime.UtcNow > deadline) throw;
                System.Threading.Thread.Sleep(15000);
            }
        }
        foreach (var entry in vmRecs)
            Console.WriteLine($"  {Host.get_name_label(session, entry.Key.opaque_ref)} " +
                              $"rated {entry.Value[1]}");

        // The appliance's own settings are read and written as one flat map of strings. Send a
        // nightly reporting schedule, then read the configuration back to confirm it took.
        Pool.send_wlb_configuration(session, new Dictionary<string, string> { ["ReportingCronString"] = "0 3 * * *" });
        var wlbConfig = Pool.retrieve_wlb_configuration(session);
        Console.WriteLine("  appliance configuration: " +
            string.Join(", ", wlbConfig.OrderBy(kv => kv.Key).Select(kv => $"{kv.Key}={kv.Value}")));
    }
    finally
    {
        // Disconnect from the appliance however the above went, or the pool stays attached to it.
        Pool.deconfigure_wlb(session);
        if (certName != "") Pool.certificate_uninstall(session, certName);
    }
    Console.WriteLine("OK: wlb-recommendations");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
WLB: wlb.example:8012
  move web-01 -> host 00000001-0000-0000-5300-000000000000 (Optimizing pool CPU load)
  move cache-01 -> host 00000001-0000-0000-5300-000000000000 (Optimizing pool CPU load)
  sdk-host1 rated 1.0
  sdk-host2 rated 3.7
  appliance configuration: ReportingCronString=0 3 * * *
OK: wlb-recommendations
```

</details>

## Python

Source: [`python/hosts_and_pools/wlb_recommendations.py`](../../python/hosts_and_pools/wlb_recommendations.py)

```python
"""Read workload-balancing recommendations.

Point the pool at a workload-balancing appliance, read its placement recommendations for the pool
and for one VM, then disconnect it.

Run it::

    wlb_recommendations("https://xenserver", "root", password, "web-01",
    wlb_host_port="192.0.2.60:30601", wlb_username="wlbuser", wlb_password="wlbpass",
    wlb_certificate="wlb-appliance.pem")
"""

import time

import XenAPI

from connection import connect


def wlb_recommendations(url, username, password, vm_name, wlb_host_port="wlb.example:8012",
                         wlb_username="wlbuser", wlb_password="wlbpass", wlb_certificate=""):
    """Connect a workload-balancing appliance and read its placement advice.

    Needs a real, reachable WLB appliance: pool.initialize_wlb makes a synchronous HTTP call to it
    and raises WLB_CONNECTION_REFUSED/WLB_CONNECTION_RESET if it can't connect - there is no way to
    fake this with a placeholder. wlb_host_port is host:port, with no URL scheme - that is the
    real wire format (xe pool-initialize-wlb wlb_url="10.x.x.x:30601" ...), not a URL.

    The pool checks the appliance's TLS certificate (pool.wlb_verify_cert), and only against the
    certificates installed with pool.certificate_install - not install_trusted_certificate's. A
    fresh appliance has a self-signed one, so pass it as wlb_certificate (a PEM file): without it
    initialize_wlb fails with INTERNAL_ERROR "Connection failed: configuration failed." and no
    hint that the certificate is the reason."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    cert_name = ""
    if wlb_certificate:
        cert_name = "sdk-example-wlb.pem"
        with open(wlb_certificate) as f:
            x.pool.certificate_install(cert_name, f.read())   # a pool-wide call: no pool argument
    x.pool.initialize_wlb(wlb_host_port, wlb_username, wlb_password, username, password)
    try:
        # Initializing connects the pool to the appliance but leaves balancing off: every WLB call
        # after this would fail WLB_DISABLED until it's switched on.
        x.pool.set_wlb_enabled(pool, True)
        print(f"WLB: {x.pool.get_wlb_url(pool)}")

        # Read BY POSITION, and the two calls do not share a shape. The pool's recommendations are
        # keyed by VM and say where to move it: [0] "wlb", [1] the destination host's UUID (a uuid,
        # not a ref), [2] and [3] ids, [4] the reason. A freshly connected pool has none yet.
        for vm_ref, fields in x.pool.retrieve_wlb_recommendations().items():
            print(f"  move {x.VM.get_name_label(vm_ref)} -> host {fields[1]} ({fields[4]})")

        # A VM's own recommendations are keyed by host and star-rate each as a destination:
        # [0] "wlb", [1] the rating - higher is better (a real appliance rated hosts 6.1 here, so not capped
        # at five). Right after connecting, the appliance is still discovering the pool: WLB_INTERNAL_ERROR
        # 4024 ("Pool discovery has not been started"), 4025 ("... has not been completed"), then 4016 ("WLB
        # does not have current metrics") - keep asking.
        vm = x.VM.get_by_name_label(vm_name)[0]
        deadline = time.time() + 600
        while True:
            try:
                ratings = x.VM.retrieve_wlb_recommendations(vm)
                break
            except XenAPI.Failure as e:
                if (e.details[0] != "WLB_INTERNAL_ERROR" or e.details[1:2] not in (["4024"], ["4025"], ["4016"])
                        or time.time() > deadline):
                    raise
                time.sleep(15)
        for host, fields in ratings.items():
            print(f"  {x.host.get_name_label(host)} rated {fields[1]}")

        # The appliance's own settings are read and written as one flat map of strings. Send a
        # nightly reporting schedule, then read the configuration back to confirm it took.
        x.pool.send_wlb_configuration({"ReportingCronString": "0 3 * * *"})
        config = x.pool.retrieve_wlb_configuration()
        print("  appliance configuration: %s"
              % ", ".join("%s=%s" % kv for kv in sorted(config.items())))
    finally:
        # Disconnect from the appliance however the above went, or the pool stays attached to it.
        x.pool.deconfigure_wlb()
        if cert_name:
            x.pool.certificate_uninstall(cert_name)
    print("OK: wlb-recommendations")
    x.session.logout()
```

<details><summary>Example output</summary>

```text
WLB: wlb.example:8012
  move cache-01 -> host 00000001-0000-0000-5300-000000000000 (Optimizing pool CPU load)
  move web-01 -> host 00000001-0000-0000-5300-000000000000 (Optimizing pool CPU load)
  sdk-host1 rated 1.0
  sdk-host2 rated 3.7
  appliance configuration: ReportingCronString=0 3 * * *
OK: wlb-recommendations
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/WlbRecommendations.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/WlbRecommendations.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

import static com.xenserver.samples.PoolConnection.connect;

public final class WlbRecommendations {
    private WlbRecommendations() {
    }

    /**
     * Read workload-balancing recommendations.
     *
     * <p>Point the pool at a workload-balancing appliance, read its placement recommendations for the pool
     * and for one VM, then disconnect it.
     *
     * <p>Connect a workload-balancing appliance and read its placement advice.
     *
     * <p>Needs a real, reachable WLB appliance: pool.initializeWlb makes a synchronous HTTP call to it and
     * raises WLB_CONNECTION_REFUSED/WLB_CONNECTION_RESET if it can't connect - there is no way to fake
     * this with a placeholder. wlbHostPort is host:port, with no URL scheme - that is the real wire format
     * (xe pool-initialize-wlb wlb_url="10.x.x.x:30601" ...), not a URL.
     *
     * <p>The pool checks the appliance's TLS certificate (pool.wlb_verify_cert), and only against the
     * certificates installed with Pool.certificateInstall - not install_trusted_certificate's. A fresh
     * appliance has a self-signed one, so pass it as wlbCertificate (a PEM file): without it initializeWlb
     * fails with INTERNAL_ERROR "Connection failed: configuration failed." and no hint that the
     * certificate is the reason.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * WlbRecommendations.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName,
            String wlbHostPort, String wlbUsername, String wlbPassword, String wlbCertificate) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            String certName = "";
            if (!wlbCertificate.isEmpty()) {
                certName = "sdk-example-wlb.pem";
                String cert = java.nio.file.Files.readString(java.nio.file.Path.of(wlbCertificate));
                Pool.certificateInstall(conn, certName, cert); // a pool-wide call: no pool argument
            }
            Pool.initializeWlb(conn, wlbHostPort, wlbUsername, wlbPassword, user, password);
            try {
                // Initializing connects the pool to the appliance but leaves balancing off: every WLB
                // call after this would fail WLB_DISABLED until it's switched on.
                Pool pool = Pool.getAll(conn).iterator().next();
                pool.setWlbEnabled(conn, true);
                System.out.println("WLB: " + pool.getWlbUrl(conn));

                // Other bindings read these BY POSITION -- [0] "wlb", [1] the destination host's UUID,
                // [2] and [3] ids, [4] the reason -- but Java CANNOT, and this is the one example where
                // the binding's type matters more than the API's.
                //
                // The datamodel declares the value as `Set String`, so this binding hands back a real
                // java.util.Set. Two things follow, and neither is visible from C#, whose binding uses
                // String[]: equal elements collapse, and iteration order is not the wire order. Indexing
                // a copy of the set returns whichever element happens to land there -- in testing, index
                // 1 was the reason and index 4 the "wlb" tag. So print the whole recommendation and let
                // a human read it; a program that needs the fields must use an ordered binding or the
                // raw JSON.
                for (Map.Entry<VM, Set<String>> rec : Pool.retrieveWlbRecommendations(conn).entrySet()) {
                    System.out.println("  move " + rec.getKey().getNameLabel(conn)
                            + ": " + String.join(" ", rec.getValue()));
                }

                // Same caveat for a VM's own recommendations, which are keyed by host and rate each as a
                // destination - higher is better (a real appliance rated hosts 6.1 here, so not capped
                // at five). Right after connecting, the appliance is still discovering the pool and
                // answers WLB_INTERNAL_ERROR 4024 ("Pool discovery has not been started") - keep asking
                // for a while. The generated binding drops WLB_INTERNAL_ERROR's parameters (its no-arg
                // constructor discards errorDescription), so unlike the other bindings this cannot check
                // for 4024 specifically and retries on any WlbInternalError instead.
                VM vm = VM.getByNameLabel(conn, vmName).iterator().next();
                long deadline = System.currentTimeMillis() + 10 * 60 * 1000;
                Map<Host, Set<String>> vmRecs;
                while (true) {
                    try {
                        vmRecs = vm.retrieveWlbRecommendations(conn);
                        break;
                    } catch (Types.WlbInternalError e) {
                        if (System.currentTimeMillis() > deadline) throw e;
                        Thread.sleep(15000);
                    }
                }
                for (Map.Entry<Host, Set<String>> rec : vmRecs.entrySet()) {
                    System.out.println("  " + rec.getKey().getNameLabel(conn)
                            + ": " + String.join(" ", rec.getValue()));
                }

                // The appliance's own settings are read and written as one flat map of strings. Send a
                // nightly reporting schedule, then read the configuration back to confirm it took.
                Map<String, String> wlbConfig = new HashMap<>();
                wlbConfig.put("ReportingCronString", "0 3 * * *");
                Pool.sendWlbConfiguration(conn, wlbConfig);
                Map<String, String> config = new TreeMap<>(Pool.retrieveWlbConfiguration(conn));
                StringBuilder cfgStr = new StringBuilder();
                for (Map.Entry<String, String> kv : config.entrySet()) {
                    if (cfgStr.length() > 0) cfgStr.append(", ");
                    cfgStr.append(kv.getKey()).append("=").append(kv.getValue());
                }
                System.out.println("  appliance configuration: " + cfgStr);
            } finally {
                // Disconnect from the appliance however the above went, or the pool stays attached to it.
                Pool.deconfigureWlb(conn);
                if (!certName.isEmpty()) Pool.certificateUninstall(conn, certName);
            }
            System.out.println("OK: wlb-recommendations");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
WLB: wlb.example:8012
  move web-01: 00000001-0000-0000-5300-000000000000 rec-1 Optimizing pool CPU load opt-1 wlb
  move cache-01: 00000001-0000-0000-5300-000000000000 rec-2 Optimizing pool CPU load opt-2 wlb
  sdk-host1: 1.0 wlb id-00000001
  sdk-host2: wlb 3.7 id-00000001
  appliance configuration: ReportingCronString=0 3 * * *
OK: wlb-recommendations
```

</details>

## Go

Source: [`go/wlb_recommendations.go`](../../go/wlb_recommendations.go)

```go
package main

import (
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
	"time"

	"go/xenapi"
)

// wlbRecommendations needs a real, reachable WLB appliance: pool.InitializeWlb makes a synchronous
// HTTP call to it and raises WLB_CONNECTION_REFUSED/WLB_CONNECTION_RESET if it can't connect -
// there is no way to fake this with a placeholder. wlbHostPort is host:port, with no URL scheme -
// that is the real wire format (xe pool-initialize-wlb wlb_url="10.x.x.x:30601" ...), not a URL.
//
// The pool checks the appliance's TLS certificate (pool.wlb_verify_cert), and only against the
// certificates installed with Pool.CertificateInstall - not install_trusted_certificate's. A fresh
// appliance has a self-signed one, so pass it as wlbCertificate (a PEM file): without it
// InitializeWlb fails with INTERNAL_ERROR "Connection failed: configuration failed." and no hint
// that the certificate is the reason.
func wlbRecommendations(url, user, password, vmName, wlbHostPort, wlbUsername, wlbPassword, wlbCertificate string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred WLB tidy-up below, which needs the session.
	defer session.Logout()

	certName := ""
	if wlbCertificate != "" {
		certName = "sdk-example-wlb.pem"
		cert, err := os.ReadFile(wlbCertificate)
		check(err)
		check(xenapi.Pool.CertificateInstall(session, certName, string(cert))) // pool-wide: no pool argument
	}
	check(xenapi.Pool.InitializeWlb(session, wlbHostPort, wlbUsername, wlbPassword, user, password))
	defer func() {
		// Disconnect from the appliance however the above went, or the pool stays attached to it.
		check(xenapi.Pool.DeconfigureWlb(session))
		if certName != "" {
			check(xenapi.Pool.CertificateUninstall(session, certName))
		}
	}()

	// Initializing connects the pool to the appliance but leaves balancing off: every WLB call after
	// this would fail WLB_DISABLED until it's switched on.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	check(xenapi.Pool.SetWlbEnabled(session, pools[0], true))
	wlbURL, _ := xenapi.Pool.GetWlbURL(session, pools[0])
	fmt.Printf("WLB: %s\n", wlbURL)

	// Read BY POSITION, and the two calls do not share a shape. The pool's are keyed by VM and say
	// where to move it: [0] "wlb", [1] the destination host's UUID (a uuid, not a ref), [2] and [3]
	// ids, [4] the reason.
	poolRecs, err := xenapi.Pool.RetrieveWlbRecommendations(session)
	check(err)
	for vmRef, fields := range poolRecs {
		name, _ := xenapi.VM.GetNameLabel(session, vmRef)
		fmt.Printf("  move %s -> host %s (%s)\n", name, fields[1], fields[4])
	}

	// A VM's own are keyed by host and star-rate each destination: [0] "wlb", [1] the rating - higher
	// is better (a real appliance rated hosts 6.1 here, so not capped at five).
	// Right after connecting, the appliance is still discovering the pool and answers
	// WLB_INTERNAL_ERROR 4024 ("Pool discovery has not been started"), 4025 ("... has not been
	// completed"), then 4016 ("WLB does not have current metrics") - keep asking for a while.
	vms, err := xenapi.VM.GetByNameLabel(session, vmName)
	check(err)
	deadline := time.Now().Add(10 * time.Minute)
	var vmRecs map[xenapi.HostRef][]string
	for {
		vmRecs, err = xenapi.VM.RetrieveWlbRecommendations(session, vms[0])
		if err == nil || !isWlbStillDiscovering(err) || time.Now().After(deadline) {
			check(err)
			break
		}
		time.Sleep(15 * time.Second)
	}
	for hostRef, fields := range vmRecs {
		name, _ := xenapi.Host.GetNameLabel(session, hostRef)
		fmt.Printf("  %s rated %s\n", name, fields[1])
	}

	// The appliance's own settings are read and written as one flat map of strings. Send a nightly
	// reporting schedule, then read the configuration back to confirm it took.
	check(xenapi.Pool.SendWlbConfiguration(session, map[string]string{"ReportingCronString": "0 3 * * *"}))
	config, err := xenapi.Pool.RetrieveWlbConfiguration(session)
	check(err)
	keys := make([]string, 0, len(config))
	for k := range config {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	pairs := make([]string, 0, len(keys))
	for _, k := range keys {
		pairs = append(pairs, fmt.Sprintf("%s=%s", k, config[k]))
	}
	fmt.Printf("  appliance configuration: %s\n", strings.Join(pairs, ", "))

	fmt.Println("OK: wlb-recommendations")
}

// isWlbStillDiscovering reports whether err is a WLB_INTERNAL_ERROR whose WLB code is 4024, 4025 or
// 4016 - the appliance is still discovering the pool, or has no metrics for it yet. See
// coordinatorFromSlaveError for why the data slice has to be parsed out of the formatted error string.
func isWlbStillDiscovering(err error) bool {
	msg := err.Error()
	if !strings.Contains(msg, xenapi.ErrorWlbInternalError) {
		return false
	}
	m := regexp.MustCompile(`data \[(.+)\]`).FindStringSubmatch(msg)
	if m == nil {
		return false
	}
	fields := strings.Fields(m[1])
	// The binding prints the code in the message and only its parameters in data: [4024 Pool ...].
	return len(fields) > 0 && (fields[0] == "4024" || fields[0] == "4025" || fields[0] == "4016")
}
```

<details><summary>Example output</summary>

```text
WLB: wlb.example:8012
  move cache-01 -> host 00000001-0000-0000-5300-000000000000 (Optimizing pool CPU load)
  move web-01 -> host 00000001-0000-0000-5300-000000000000 (Optimizing pool CPU load)
  sdk-host2 rated 3.7
  sdk-host1 rated 1.0
  appliance configuration: ReportingCronString=0 3 * * *
OK: wlb-recommendations
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-WlbRecommendations.ps1`](../../powershell/HostsAndPools/Invoke-WlbRecommendations.ps1)

```powershell
function Invoke-WlbRecommendations {
    <#
    .SYNOPSIS
        Read workload-balancing recommendations.
    .DESCRIPTION
        Point the pool at a workload-balancing appliance, read its placement recommendations for the pool
        and for one VM, then disconnect it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = "web-01",
        [string]$WlbHostPort = "wlb.example:8012",
        [string]$WlbUsername = "wlbuser",
        [string]$WlbPassword = "wlbpass",
        [string]$WlbCertificate = ""
    )
    # Needs a real, reachable WLB appliance: InitializeWlb makes a synchronous HTTP call to it and raises
    # WLB_CONNECTION_REFUSED/WLB_CONNECTION_RESET if it can't connect - there is no way to fake this with
    # a placeholder. WlbHostPort is host:port, with NO URL scheme - that is the real wire format
    # (xe pool-initialize-wlb wlb_url="10.x.x.x:30601" ...), not a URL.
    #
    # The pool checks the appliance's TLS certificate (wlb_verify_cert), and only against the
    # certificates installed with -XenAction CertificateInstall - not InstallTrustedCertificate's. A
    # fresh appliance has a self-signed one, so pass it as WlbCertificate (a PEM file): without it
    # InitializeWlb fails with INTERNAL_ERROR "Connection failed: configuration failed." and no hint
    # that the certificate is the reason.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    $certName = ""
    if ($WlbCertificate) {
        $certName = "sdk-example-wlb.pem"
        Invoke-XenPool -Ref $pool.opaque_ref -XenAction CertificateInstall `
            -NameParam $certName -Cert (Get-Content -Raw $WlbCertificate)   # pool-wide: no -Pool/-Ref target
    }
    Invoke-XenPool -Ref $pool.opaque_ref -XenAction InitializeWlb `
        -WlbUrl $WlbHostPort -WlbUsername $WlbUsername -WlbPassword $WlbPassword `
        -XenserverUsername $UserName -XenserverPassword $Password
    try {
        # Initializing connects the pool to the appliance but leaves balancing off: every WLB call
        # after this would fail WLB_DISABLED until it's switched on.
        Set-XenPool -Pool $pool -WlbEnabled $true
        Write-Host "WLB: $((Get-XenPool | Select-Object -First 1).wlb_url)"

        # Read BY POSITION, and the two calls do not share a shape. The pool's are keyed by VM and say
        # where to move it: [0] "wlb", [1] the destination host's UUID (a uuid, not a ref), [2] and [3]
        # ids, [4] the reason.
        # -PassThru: without it Invoke-Xen* runs the action and emits nothing, so a value-returning
        # action looks like it returned null.
        $poolRecs = Invoke-XenPool -Ref $pool.opaque_ref -XenAction RetrieveWlbRecommendations -PassThru
        foreach ($entry in $poolRecs.GetEnumerator()) {
            $fields = @($entry.Value)
            $name = (Get-XenVM -Ref $entry.Key).name_label
            Write-Host "  move $name -> host $($fields[1]) ($($fields[4]))"
        }

        # A VM's own are keyed by host and star-rate each destination: [0] "wlb", [1] the rating -
        # higher is better (a real appliance rated hosts 6.1 here, so not capped at five). Right
        # after connecting, the appliance is still discovering the pool and answers
        # WLB_INTERNAL_ERROR 4024 ("Pool discovery has not been started"), 4025 ("... has not been
        # completed"), then 4016 ("WLB does not have current metrics") - keep asking for a while.
        $vm = Get-XenVM -Name $VmName
        $deadline = (Get-Date).AddMinutes(10)
        while ($true) {
            try { $vmRecs = Invoke-XenVM -Ref $vm.opaque_ref -XenAction RetrieveWlbRecommendations -PassThru; break }
            catch {
                $ex = $_.Exception
                while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
                if (-not ($ex -and $ex.ErrorDescription -and $ex.ErrorDescription[0] -eq "WLB_INTERNAL_ERROR" `
                        -and $ex.ErrorDescription[1] -in "4024", "4025", "4016") -or (Get-Date) -gt $deadline) {
                    throw
                }
                Start-Sleep -Seconds 15
            }
        }
        foreach ($entry in $vmRecs.GetEnumerator()) {
            $fields = @($entry.Value)
            Write-Host "  $((Get-XenHost -Ref $entry.Key).name_label) rated $($fields[1])"
        }

        # The appliance's own settings are read and written as one flat map of strings. Send a nightly
        # reporting schedule, then read the configuration back to confirm it took.
        Invoke-XenPool -Ref $pool.opaque_ref -XenAction SendWlbConfiguration -Config @{ ReportingCronString = "0 3 * * *" }
        $config = Invoke-XenPool -Ref $pool.opaque_ref -XenAction RetrieveWlbConfiguration -PassThru
        $pairs = $config.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }
        Write-Host "  appliance configuration: $($pairs -join ', ')"
    }
    finally {
        # Disconnect from the appliance however the above went, or the pool stays attached to it.
        Invoke-XenPool -Ref $pool.opaque_ref -XenAction DeconfigureWlb
        if ($certName) { Invoke-XenPool -Ref $pool.opaque_ref -XenAction CertificateUninstall -NameParam $certName }
    }
    Write-Host "OK: wlb-recommendations"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
WLB: wlb.example:8012
  move cache-01 -> host 00000001-0000-0000-5300-000000000000 (Optimizing pool CPU load)
  move web-01 -> host 00000001-0000-0000-5300-000000000000 (Optimizing pool CPU load)
  sdk-host1 rated 1.0
  sdk-host2 rated 3.7
  appliance configuration: ReportingCronString=0 3 * * *
OK: wlb-recommendations
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/wlb-recommendations.sh`](../../cli/hosts-and-pools/wlb-recommendations.sh)

```bash
# Read workload-balancing recommendations.
#
# Point the pool at a workload-balancing appliance, read its placement recommendations for the pool and for
# one VM, then disconnect it.
#
# Run it:
#   ./workflows.sh wlb-recommendations https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (web-01)
#   wlb_host_port (wlb.example:8012)
#   wlb_username (wlbuser)
#   wlb_password (wlbpass)
#   wlb_certificate ("")

# Needs a real, reachable WLB appliance: pool-initialize-wlb makes a synchronous HTTP call to it and fails
# if it can't connect - there is no way to fake this with a placeholder. wlb_host_port is host:port, with
# NO URL scheme - that is the real wire format (as a real pool sends it), not a URL; the old hard-coded
# value had an incorrect "https://" prefix. Also note: this command's own parameter names are an exception
# to xe's usual hyphenated convention - they are genuinely underscored on the wire.
#
# The pool checks the appliance's TLS certificate (wlb-verify-cert), and only against the certificates
# installed with pool-certificate-install - not pool-install-trusted-certificate's (a different store).
# A fresh appliance has a self-signed one, so pass it as wlb_certificate (a PEM file): without it
# pool-initialize-wlb fails with "Connection failed: configuration failed." and no hint that the
# certificate is the reason. pool-certificate-install is deprecated for pool-install-ca-certificate, but
# it is the same call either way (xapi_pool.ml aliases them) - and it names the certificate after the
# file's own basename rather than taking a name= parameter, so the file is copied to the name wanted
# for uninstalling it again.
wlb_recommendations() {
    local vm_name wlb_host_port wlb_username wlb_password wlb_certificate vm pool out deadline
    # Not local: the EXIT trap below reads it after this function has returned.
    wlb_cert_name=""
    vm_name=$(param vm_name "web-01")
    wlb_host_port=$(param wlb_host_port "wlb.example:8012")
    wlb_username=$(param wlb_username "wlbuser")
    wlb_password=$(param wlb_password "wlbpass")
    wlb_certificate=$(param wlb_certificate "")

    if [ -n "$wlb_certificate" ]; then
        wlb_cert_name=sdk-example-wlb.pem
        cp "$wlb_certificate" "$wlb_cert_name"
        xe pool-certificate-install filename="$wlb_cert_name"
        rm -f "$wlb_cert_name"
    fi
    xe pool-initialize-wlb wlb_url="$wlb_host_port" wlb_username="$wlb_username" \
        wlb_password="$wlb_password" xenserver_username="$user" xenserver_password="$pass"

    # Disconnect from the appliance however the rest of this goes, or the pool stays attached to it. This
    # script dispatches to exactly one workflow and then exits, so an EXIT trap is bash's try/finally.
    trap 'xe pool-deconfigure-wlb; [ -z "$wlb_cert_name" ] || xe pool-certificate-uninstall name="$wlb_cert_name"' EXIT

    # Initializing connects the pool to the appliance but leaves balancing off: every WLB call after this
    # would fail WLB_DISABLED until it's switched on.
    pool=$(xe pool-list --minimal)
    xe pool-param-set uuid=$pool wlb-enabled=true
    echo "WLB: $(xe pool-list params=wlb-url --minimal)"

    # One line per recommendation, keyed by VM: "wlb", the destination host UUID, two ids, the reason.
    xe pool-retrieve-wlb-recommendations

    # A VM's own recommendations are keyed by host and star-rate each as a destination - higher is better
    # (a real appliance rated hosts 6.1 here, so not capped at five). Right after connecting, the appliance
    # is still discovering the pool: WLB_INTERNAL_ERROR 4024 ("Pool discovery has not been started"), 4025
    # ("... has not been completed"), then 4016 ("WLB does not have current metrics") - keep asking for a
    # while. xe prints the error's message, not its code, so match on the text.
    vm=$(vm_uuid "$vm_name")
    deadline=$((SECONDS + 600))
    while true; do
        if out=$(xe vm-retrieve-wlb-recommendations uuid=$vm 2>&1); then break; fi
        case "$out" in
            *4024*|*4025*|*"Pool discovery has not been"*|*4016*|*"does not have current metrics"*) ;;
            *) echo "$out" >&2; exit 1 ;;
        esac
        if [ $SECONDS -gt $deadline ]; then echo "$out" >&2; exit 1; fi
        sleep 15
    done
    printf '%s\n' "$out"

    # The appliance's own settings are read and written as one flat map of strings. Send a nightly
    # reporting schedule, then read the configuration back to confirm it took.
    xe pool-send-wlb-configuration config:ReportingCronString="0 3 * * *"
    echo "  appliance configuration: $(xe pool-retrieve-wlb-configuration)"

    echo "OK: wlb-recommendations"
}
```

<details><summary>Example output</summary>

```text
WLB: wlb.example:8012
web-01: wlb 00000001-0000-0000-5300-000000000000 opt-1 rec-1 Optimizing pool CPU load
cache-01: wlb 00000001-0000-0000-5300-000000000000 opt-2 rec-2 Optimizing pool CPU load
sdk-host1: wlb 1.0 id-00000001
sdk-host2: wlb 3.7 id-00000001
  appliance configuration: ReportingCronString: 0 3 * * *
OK: wlb-recommendations
```

</details>
