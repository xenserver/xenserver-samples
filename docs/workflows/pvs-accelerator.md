<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# PVS Accelerator inventory

Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host, size, storage), its PVS servers (addresses and streaming port range), and which VMs are accelerated versus the whole pool.

Workflow `pvs-accelerator`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-PvsAccelerator.ps1`](../../powershell/HostsAndPools/Invoke-PvsAccelerator.ps1)

```powershell
function Invoke-PvsAccelerator {
    <#
    .SYNOPSIS
        PVS Accelerator inventory.
    .DESCRIPTION
        Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host, size,
        storage), its PVS servers (addresses and streaming port range), and which VMs are accelerated versus
        the whole pool.
    .EXAMPLE
        Invoke-PvsAccelerator -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $sites = @(Get-XenPVSSite)
    if ($sites.Count -eq 0) { Write-Host "No PVS Accelerator sites are configured." }
    foreach ($site in $sites) {
        Write-Host "Site: $($site.name_label)"
        foreach ($csRef in $site.cache_storage) {
            $cs = Get-XenPVSCacheStorage -Ref $csRef.opaque_ref
            $cacheHost = Get-XenHost -Ref $cs.host.opaque_ref
            $sr = Get-XenSR -Ref $cs.SR.opaque_ref
            Write-Host ("  cache:  $($cacheHost.name_label)  $([long]($cs.size / 1GB)) GiB on $($sr.name_label)")
        }
        foreach ($serverRef in $site.servers) {
            $server = Get-XenPVSServer -Ref $serverRef.opaque_ref
            Write-Host ("  server: $($server.addresses -join ', ')  ports $($server.first_port)-$($server.last_port)")
        }
        # Which VMs are accelerated: walk each proxy to its VIF to its VM.
        $accelerated = @{}
        foreach ($proxyRef in $site.proxies) {
            $proxy = Get-XenPVSProxy -Ref $proxyRef.opaque_ref
            $vif = Get-XenVIF -Ref $proxy.VIF.opaque_ref
            $accelerated[$vif.VM.opaque_ref] = $proxy.status
        }
        $guests = Get-XenVM | Where-Object { -not $_.is_control_domain -and -not $_.is_a_template -and -not $_.is_a_snapshot }
        $count = @($guests | Where-Object { $accelerated.ContainsKey($_.opaque_ref) }).Count
        Write-Host "  $count of $(@($guests).Count) VM(s) accelerated"
    }
    Write-Host "OK: pvs-accelerator"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Site: Provisioning Services
  cache:  sdk-host1  20 GiB on Local storage
  cache:  sdk-host2  20 GiB on Local storage
  server: 203.0.113.50  ports 6910-6930
  server: 203.0.113.51  ports 6910-6930
  1 of 4 VM(s) accelerated
OK: pvs-accelerator
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/pvs-accelerator.sh`](../../cli/hosts-and-pools/pvs-accelerator.sh)

```bash
# PVS Accelerator inventory.
#
# Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host, size, storage),
# its PVS servers (addresses and streaming port range), and which VMs are accelerated versus the whole pool.
#
# Run it:
#   ./workflows.sh pvs-accelerator https://xenserver root "$password"

pvs_accelerator() {
    sites=$(xe pvs-site-list --minimal)
    if [ -z "$sites" ]; then echo "No PVS Accelerator sites are configured."; echo "OK: pvs-accelerator"; return; fi
    for site in ${sites//,/ }; do
        echo "Site: $(xe pvs-site-param-get uuid=$site param-name=name-label)"
        cslist=$(xe pvs-cache-storage-list --minimal)
        for cs in ${cslist//,/ }; do
            h=$(xe pvs-cache-storage-param-get uuid=$cs param-name=host-uuid)
            sr=$(xe pvs-cache-storage-param-get uuid=$cs param-name=sr-uuid)
            size=$(xe pvs-cache-storage-param-get uuid=$cs param-name=size)
            echo "  cache:  $(xe host-param-get uuid=$h param-name=name-label)  $((size / 1024 / 1024 / 1024)) GiB on $(xe sr-param-get uuid=$sr param-name=name-label)"
        done
        srvlist=$(xe pvs-server-list --minimal)
        for srv in ${srvlist//,/ }; do
            echo "  server: $(xe pvs-server-param-get uuid=$srv param-name=addresses)  ports $(xe pvs-server-param-get uuid=$srv param-name=first-port)-$(xe pvs-server-param-get uuid=$srv param-name=last-port)"
        done
        # One proxy accelerates one VM in this pool, so proxy count = accelerated VM count.
        accelerated=$(count_csv "$(xe pvs-proxy-list --minimal)")
        total=$(count_csv "$(xe vm-list is-control-domain=false --minimal)")
        echo "  $accelerated of $total VM(s) accelerated"
    done
    echo "OK: pvs-accelerator"
}
```

<details><summary>Example output</summary>

```text
Site: Provisioning Services
  cache:  sdk-host1  20 GiB on Local storage
  cache:  sdk-host2  20 GiB on Local storage
  server: 203.0.113.50  ports 6910-6930
  server: 203.0.113.51  ports 6910-6930
  1 of 4 VM(s) accelerated
OK: pvs-accelerator
```

</details>

## Python

Source: [`python/hosts_and_pools/pvs_accelerator.py`](../../python/hosts_and_pools/pvs_accelerator.py)

```python
"""PVS Accelerator inventory.

Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host, size,
storage), its PVS servers (addresses and streaming port range), and which VMs are accelerated versus
the whole pool.
"""

from connection import connect


# Maps the <workflow> argument to the matching self-contained function above, supplying the
# concrete objects each one operates on. In your own scripts you would call these functions
# directly (see the "Run it:" line under each) rather than through this dispatcher.
def pvs_accelerator(url, username, password):
    session = connect(url, username, password)
    x = session.xenapi
    sites = x.PVS_site.get_all_records()
    if not sites:
        print("No PVS Accelerator sites are configured.")
    for site in sites.values():
        print("Site: %s" % site["name_label"])
        for cs_ref in site["cache_storage"]:
            cs = x.PVS_cache_storage.get_record(cs_ref)
            host = x.host.get_record(cs["host"])
            sr = x.SR.get_record(cs["SR"])
            print("  cache:  %s  %d GiB on %s" % (host["name_label"], int(cs["size"]) // (1024 ** 3), sr["name_label"]))
        for server_ref in site["servers"]:
            server = x.PVS_server.get_record(server_ref)
            print("  server: %s  ports %s-%s" % (", ".join(server["addresses"]), server["first_port"], server["last_port"]))
        # Which VMs are accelerated: walk each proxy to its VIF to its VM.
        accelerated = {}
        for proxy_ref in site["proxies"]:
            proxy = x.PVS_proxy.get_record(proxy_ref)
            vif = x.VIF.get_record(proxy["VIF"])
            accelerated[vif["VM"]] = proxy["status"]
        guests = [(ref, v) for ref, v in x.VM.get_all_records().items()
                  if not v["is_control_domain"] and not v["is_a_template"] and not v["is_a_snapshot"]]
        count = sum(1 for ref, _ in guests if ref in accelerated)
        print("  %d of %d VM(s) accelerated" % (count, len(guests)))
    print("OK: pvs-accelerator")
    session.logout()
```

<details><summary>Example output</summary>

```text
Site: Provisioning Services
  cache:  sdk-host1  20 GiB on Local storage
  cache:  sdk-host2  20 GiB on Local storage
  server: 203.0.113.50  ports 6910-6930
  server: 203.0.113.51  ports 6910-6930
  1 of 4 VM(s) accelerated
OK: pvs-accelerator
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/PvsAccelerator.cs`](../../csharp/HostsAndPools/PvsAccelerator.cs)

```csharp
/// <summary>
/// Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host, size,
/// storage), its PVS servers (addresses and streaming port range), and which VMs are accelerated versus
/// the whole pool.
/// </summary>
/// <remarks>
/// Maps the &lt;workflow&gt; argument to the matching self-contained method above, supplying the concrete
/// objects each one operates on. In your own code you would call these methods directly (see the "Run
/// it:" line under each) rather than through this dispatcher.
/// </remarks>
public static void PvsAccelerator(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var sites = PVS_site.get_all_records(session);
    if (sites.Count == 0) Console.WriteLine("No PVS Accelerator sites are configured.");
    foreach (var site in sites.Values)
    {
        Console.WriteLine($"Site: {site.name_label}");
        foreach (var csRef in site.cache_storage)
        {
            var cs = PVS_cache_storage.get_record(session, csRef.opaque_ref);
            var cacheHost = Host.get_record(session, cs.host.opaque_ref);
            var sr = SR.get_record(session, cs.SR.opaque_ref);
            Console.WriteLine($"  cache:  {cacheHost.name_label}  {cs.size / (1024L * 1024 * 1024)} GiB on {sr.name_label}");
        }
        foreach (var serverRef in site.servers)
        {
            var server = PVS_server.get_record(session, serverRef.opaque_ref);
            Console.WriteLine($"  server: {string.Join(", ", server.addresses)}  ports {server.first_port}-{server.last_port}");
        }
        // Which VMs are accelerated: walk each proxy to its VIF to its VM.
        var accelerated = new HashSet<string>();
        foreach (var proxyRef in site.proxies)
        {
            var proxy = PVS_proxy.get_record(session, proxyRef.opaque_ref);
            var vif = VIF.get_record(session, proxy.VIF.opaque_ref);
            accelerated.Add(vif.VM.opaque_ref);
        }
        var guests = VM.get_all_records(session)
            .Where(kv => !kv.Value.is_control_domain && !kv.Value.is_a_template && !kv.Value.is_a_snapshot).ToList();
        var count = guests.Count(kv => accelerated.Contains(kv.Key.opaque_ref));
        Console.WriteLine($"  {count} of {guests.Count} VM(s) accelerated");
    }
    Console.WriteLine("OK: pvs-accelerator");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Site: Provisioning Services
  cache:  sdk-host1  20 GiB on Local storage
  cache:  sdk-host2  20 GiB on Local storage
  server: 203.0.113.50  ports 6910-6930
  server: 203.0.113.51  ports 6910-6930
  1 of 4 VM(s) accelerated
OK: pvs-accelerator
```

</details>

## Go

Source: [`go/pvs_accelerator.go`](../../go/pvs_accelerator.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// pvsAccelerator - PVS Accelerator inventory.
//
// Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host,
// size, storage), its PVS servers (addresses and streaming port range), and which VMs are
// accelerated versus the whole pool.
//
// Run it:
//
//	pvsAccelerator("https://xenserver", "root", password)
func pvsAccelerator(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	sites, err := xenapi.PVSSite.GetAllRecords(session)
	check(err)
	if len(sites) == 0 {
		fmt.Println("No PVS Accelerator sites are configured.")
	}
	for _, site := range sites {
		fmt.Printf("Site: %s\n", site.NameLabel)
		for _, csRef := range site.CacheStorage {
			cs, err := xenapi.PVSCacheStorage.GetRecord(session, csRef)
			check(err)
			host, _ := xenapi.Host.GetRecord(session, cs.Host)
			sr, _ := xenapi.SR.GetRecord(session, cs.SR)
			fmt.Printf("  cache:  %s  %d GiB on %s\n", host.NameLabel, cs.Size/(1024*1024*1024), sr.NameLabel)
		}
		for _, serverRef := range site.Servers {
			server, err := xenapi.PVSServer.GetRecord(session, serverRef)
			check(err)
			fmt.Printf("  server: %s  ports %d-%d\n", strings.Join(server.Addresses, ", "), server.FirstPort, server.LastPort)
		}
		// Which VMs are accelerated: walk each proxy to its VIF to its VM.
		accelerated := map[xenapi.VMRef]bool{}
		for _, proxyRef := range site.Proxies {
			proxy, err := xenapi.PVSProxy.GetRecord(session, proxyRef)
			check(err)
			vif, err := xenapi.VIF.GetRecord(session, proxy.VIF)
			check(err)
			accelerated[vif.VM] = true
		}
		vms, err := xenapi.VM.GetAllRecords(session)
		check(err)
		total, count := 0, 0
		for ref, v := range vms {
			if v.IsControlDomain || v.IsATemplate || v.IsASnapshot {
				continue
			}
			total++
			if accelerated[ref] {
				count++
			}
		}
		fmt.Printf("  %d of %d VM(s) accelerated\n", count, total)
	}
	fmt.Println("OK: pvs-accelerator")
}
```

<details><summary>Example output</summary>

```text
Site: Provisioning Services
  cache:  sdk-host1  20 GiB on Local storage
  cache:  sdk-host2  20 GiB on Local storage
  server: 203.0.113.50  ports 6910-6930
  server: 203.0.113.51  ports 6910-6930
  1 of 4 VM(s) accelerated
OK: pvs-accelerator
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/PvsAccelerator.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/PvsAccelerator.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.PVSCacheStorage;
import com.xensource.xenapi.PVSProxy;
import com.xensource.xenapi.PVSServer;
import com.xensource.xenapi.PVSSite;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class PvsAccelerator {
    private PvsAccelerator() {
    }

    /**
     * PVS Accelerator inventory.
     *
     * <p>Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host,
     * size, storage), its PVS servers (addresses and streaming port range), and which VMs are accelerated
     * versus the whole pool.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Map<PVSSite, PVSSite.Record> sites = PVSSite.getAllRecords(conn);
            if (sites.isEmpty()) System.out.println("No PVS Accelerator sites are configured.");
            for (PVSSite.Record site : sites.values()) {
                System.out.println("Site: " + site.nameLabel);
                for (PVSCacheStorage cs : site.cacheStorage) {
                    PVSCacheStorage.Record r = cs.getRecord(conn);
                    System.out.printf("  cache:  %s  %d GiB on %s%n",
                        r.host.getNameLabel(conn), r.size / (1024L * 1024 * 1024), r.SR.getNameLabel(conn));
                }
                for (PVSServer server : site.servers) {
                    PVSServer.Record r = server.getRecord(conn);
                    System.out.printf("  server: %s  ports %d-%d%n", String.join(", ", r.addresses), r.firstPort, r.lastPort);
                }
                // Which VMs are accelerated: walk each proxy to its VIF to its VM.
                java.util.Set<String> accelerated = new java.util.HashSet<>();
                for (PVSProxy proxy : site.proxies) {
                    VIF vif = proxy.getRecord(conn).VIF;
                    accelerated.add(vif.getRecord(conn).VM.toWireString());
                }
                int total = 0, count = 0;
                for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                    VM.Record v = e.getValue();
                    if (v.isControlDomain || v.isATemplate || v.isASnapshot) continue;
                    total++;
                    if (accelerated.contains(e.getKey().toWireString())) count++;
                }
                System.out.printf("  %d of %d VM(s) accelerated%n", count, total);
            }
            System.out.println("OK: pvs-accelerator");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
Site: Provisioning Services
  cache:  sdk-host2  20 GiB on Local storage
  cache:  sdk-host1  20 GiB on Local storage
  server: 203.0.113.50  ports 6910-6930
  server: 203.0.113.51  ports 6910-6930
  1 of 4 VM(s) accelerated
OK: pvs-accelerator
```

</details>
