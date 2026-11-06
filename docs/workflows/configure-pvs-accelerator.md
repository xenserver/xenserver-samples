<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure PVS Accelerator

Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS server, put a read cache on each host's local storage, accelerate a VM by proxying its first NIC, then remove the proxy and the server and forget the site, which removes its cache storage.

Workflow `configure-pvs-accelerator`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ConfigurePvsAccelerator.ps1`](../../powershell/HostsAndPools/Invoke-ConfigurePvsAccelerator.ps1)

```powershell
function Invoke-ConfigurePvsAccelerator {
    <#
    .SYNOPSIS
        Configure PVS Accelerator.
    .DESCRIPTION
        Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS
        server, put a read cache on each host's local storage, accelerate a VM by proxying its first NIC,
        then forget the site — which cascades to everything hanging off it.
    .EXAMPLE
        Invoke-ConfigurePvsAccelerator -Url https://xenserver -UserName root -Password $password -VmName 'db-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # Check the VM first, before creating anything: it needs a NIC for the proxy to sit on. It need not
    # be running - a proxy on a halted VM just reports "stopped" until it starts.
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    # A proxy may only sit on the VM's LOWEST-numbered NIC, so sort by device rather than taking the
    # first VIF — the list comes back in creation order, which is the same thing only by luck.
    $vif = $vm.VIFs | ForEach-Object { Get-XenVIF -Ref $_ } |
        Sort-Object { [int]$_.device } | Select-Object -First 1
    if (-not $vif) { throw "$VmName has no network interface to accelerate" }
    # ... and one that no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT).
    $existing = Get-XenPVSProxy | Where-Object { $_.VIF -eq $vif } | Select-Object -First 1
    if ($existing) {
        throw "$VmName is already accelerated by site '$((Get-XenPVSSite -Ref $existing.site).name_label)'"
    }

    # PVS_site.introduce and PVS_server.introduce are CONSTRUCTORS, and every parameter set of
    # Invoke-XenPVSSite / Invoke-XenPVSServer identifies an object that ALREADY EXISTS (-PVSSite / -Ref /
    # -Uuid / -Name). Introduce is in the -XenAction enum, but there is no way to call it: name an object
    # and it goes looking for one that isn't there yet; name none and PowerShell cannot choose between
    # four sets, so it fails at binding with AmbiguousParameterSet before the call is even attempted.
    # Same shape as Cluster.pool_create in configure-clustering — so, same answer: call the method over
    # JSON-RPC. Still pure PowerShell; no [XenAPI.*]:: statics.
    $site = Invoke-XenMethod -Session $session -Method 'PVS_site.introduce' `
        -Params @('sdk-example-pvs', 'Created by the SDK examples', '')
    Invoke-XenMethod -Session $session -Method 'PVS_server.introduce' `
        -Params @(@('203.0.113.90'), 6910, 6930, $site) | Out-Null

    # The read cache should be on LOCAL storage: keeping reads off the network is the point, and the
    # server does not enforce that, but a cache on shared storage rarely makes sense and can't be
    # shared between hosts anyway. New-XenPVSCacheStorage is a real cmdlet.
    foreach ($xenHost in Get-XenHost) {
        $local = Get-XenPBD | Where-Object { $_.host -eq $xenHost } |
            ForEach-Object { Get-XenSR -Ref $_.SR } |
            Where-Object { -not $_.shared -and $_.content_type -ne 'iso' -and $_.type -ne 'udev' } |
            Select-Object -First 1
        if (-not $local) { continue }
        New-XenPVSCacheStorage -XenHost $xenHost -SR $local -Site $site `
            -Size 10GB | Out-Null
    }

    $proxy = New-XenPVSProxy -Site $site -VIF $vif -PassThru

    $record = Get-XenPVSSite -Ref $site
    Write-Host "Site '$($record.name_label)' with $($record.cache_storage.Count) cache(s) and $($record.servers.Count) server(s)"
    # "caching" means it is really accelerating: a site with no cache reports "initialised", and a proxy
    # on a VM whose NIC is unplugged reports "stopped".
    Write-Host "  $($vm.name_label): $($proxy.status)"

    # Forgetting the site only cascades its cache storage - a running proxy or a server it still has
    # makes forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down ourselves
    # first, in the same order every real PVS teardown uses. (Cache storage doesn't need a separate
    # call - forget cascades it correctly.)
    Remove-XenPVSProxy -Ref $proxy
    foreach ($serverRef in (Get-XenPVSSite -Ref $site).servers) {
        Invoke-XenPVSServer -Ref $serverRef -XenAction Forget
    }
    Invoke-XenPVSSite -Ref $site -XenAction Forget
    Write-Host "OK: configure-pvs-accelerator"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Site 'sdk-example-pvs' with 2 cache(s) and 1 server(s)
  db-01: stopped
OK: configure-pvs-accelerator
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/configure-pvs-accelerator.sh`](../../cli/hosts-and-pools/configure-pvs-accelerator.sh)

```bash
# Configure PVS Accelerator.
#
# Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS server, put a
# read cache on each host's local storage, accelerate a VM by proxying its first NIC, then forget the site —
# which cascades to everything hanging off it.
#
# Run it:
#   ./workflows.sh configure-pvs-accelerator https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (db-01)

configure_pvs_accelerator() {
    local vm_name vm vif
    vm_name=$(param vm_name "db-01")
    # Check the VM first, before creating anything: it needs a NIC for the proxy to sit on, and one that
    # no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT). It need not be running
    # - a proxy on a halted VM just reports "stopped" until it starts.
    vm=$(vm_uuid "$vm_name")
    name=$(xe vm-param-get uuid=$vm param-name=name-label)
    vif=$(lowest_device_vif "$vm")
    if [ -z "$vif" ]; then
        echo "$vm_name has no network interface to accelerate" >&2
        return 1
    fi
    existing=$(xe pvs-proxy-list vif-uuid=$vif --minimal)
    if [ -n "$existing" ]; then
        existing_site=$(xe pvs-proxy-param-get uuid=$existing param-name=site-uuid)
        echo "$vm_name is already accelerated by site '$(xe pvs-site-param-get uuid=$existing_site param-name=name-label)'" >&2
        return 1
    fi

    site=$(xe pvs-site-introduce name-label=sdk-example-pvs name-description="Created by the SDK examples")
    xe pvs-server-introduce addresses=203.0.113.90 first-port=6910 last-port=6930 pvs-site-uuid="$site" >/dev/null

    # The read cache should be on LOCAL storage: keeping reads off the network is the point, and the
    # server does not enforce that, but a cache on shared storage rarely makes sense and can't be
    # shared between hosts anyway.
    for h in $(each_csv "$(xe host-list --minimal)"); do
        for pbd in $(each_csv "$(xe pbd-list host-uuid=$h --minimal)"); do
            sr=$(xe pbd-param-get uuid=$pbd param-name=sr-uuid)
            [ "$(xe sr-param-get uuid=$sr param-name=shared)" = "false" ] || continue
            [ "$(xe sr-param-get uuid=$sr param-name=content-type)" = "iso" ] && continue
            [ "$(xe sr-param-get uuid=$sr param-name=type)" = "udev" ] && continue   # removable storage
            xe pvs-cache-storage-create uuid=$h sr-uuid=$sr pvs-site-uuid="$site" size=10737418240 >/dev/null
            break
        done
    done

    # A proxy may only sit on the VM's LOWEST-numbered NIC, hence sorting by device above rather than
    # just taking the first VIF listed — the list comes back in creation order, which is the same thing
    # only by luck.
    proxy=$(xe pvs-proxy-create pvs-site-uuid="$site" vif-uuid="$vif")

    # Scoped to THIS site: the pool may already have one, and counting pool-wide would report its
    # caches and servers as though this example had made them.
    caches=$(count_csv "$(xe pvs-cache-storage-list pvs-site-uuid="$site" --minimal)")
    servers=$(count_csv "$(xe pvs-server-list pvs-site-uuid="$site" --minimal)")
    echo "Site '$(xe pvs-site-param-get uuid=$site param-name=name-label)' with $caches cache(s) and $servers server(s)"
    # "caching" means it is really accelerating: a site with no cache reports "initialised", and a
    # proxy on a VM whose NIC is unplugged reports "stopped".
    echo "  $name: $(xe pvs-proxy-param-get uuid=$proxy param-name=status)"

    # Forgetting the site only cascades its cache storage - a running proxy or a server it still has makes
    # forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down first, in the same
    # order every real PVS teardown uses.
    xe pvs-proxy-destroy uuid="$proxy"
    for srv in $(each_csv "$(xe pvs-server-list pvs-site-uuid="$site" --minimal)"); do
        xe pvs-server-forget uuid="$srv"
    done
    xe pvs-site-forget uuid="$site"
    echo "OK: configure-pvs-accelerator"
}

# The VIF with the lowest device number on a VM. (vif-list --minimal prints only uuids even when params=
# names more fields, so each VIF's device is read on its own.)
lowest_device_vif() {
    local vif dev best_uuid="" best_dev=""
    for vif in $(each_csv "$(xe vif-list vm-uuid=$1 --minimal)"); do
        dev=$(xe vif-param-get uuid=$vif param-name=device)
        if [ -z "$best_dev" ] || [ "$dev" -lt "$best_dev" ]; then best_uuid=$vif; best_dev=$dev; fi
    done
    echo "$best_uuid"
}
```

<details><summary>Example output</summary>

```text
Site 'sdk-example-pvs' with 2 cache(s) and 1 server(s)
  db-01: stopped
OK: configure-pvs-accelerator
```

</details>

## Python

Source: [`python/hosts_and_pools/configure_pvs_accelerator.py`](../../python/hosts_and_pools/configure_pvs_accelerator.py)

```python
"""Configure PVS Accelerator.

Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS
server, put a read cache on each host's local storage, accelerate a VM by proxying its first NIC,
then forget the site — which cascades to everything hanging off it.
"""

from connection import connect
from helpers import vm_by_name


def configure_pvs_accelerator(url, username, password, vm_name):
    """Build a PVS Accelerator site from nothing: a site, a PVS server, a read cache on each
    host, and one accelerated VM (vm_name). Then take it all down again.

    The inventory example above reads a configuration someone else made; this one makes it."""
    session = connect(url, username, password)
    x = session.xenapi

    # Check the VM first, before creating anything: it needs a NIC for the proxy to sit on, and one
    # that no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT). It need not be
    # running - a proxy on a halted VM just reports "stopped" until it starts.
    vm = vm_by_name(session, vm_name)
    vifs = sorted(x.VM.get_VIFs(vm), key=lambda v: int(x.VIF.get_device(v)))
    if not vifs:
        raise RuntimeError("%s has no network interface to accelerate" % vm_name)
    for proxy in x.PVS_proxy.get_all_records().values():
        if proxy["VIF"] == vifs[0]:
            raise RuntimeError("%s is already accelerated by site '%s'"
                               % (vm_name, x.PVS_site.get_name_label(proxy["site"])))

    site = x.PVS_site.introduce("sdk-example-pvs", "Created by the SDK examples", "")
    x.PVS_server.introduce(["203.0.113.90"], 6910, 6930, site)

    # The read cache should be on LOCAL storage. The point of the accelerator is to keep reads off
    # the network; xapi does not enforce that, but a cache on shared storage rarely makes sense and
    # can't be shared between hosts anyway.
    for host in x.host.get_all():
        local = local_sr(x, host)
        if local:
            # size as a STRING: XML-RPC only carries 32-bit integers, so the Python binding passes
            # every XenAPI Int as a string. 10 GiB does not fit, and passing an int raises inside
            # xmlrpc.client rather than at the API — a confusing place to land.
            x.PVS_cache_storage.create({"host": host, "SR": local, "site": site,
                                        "size": str(10 * 1024 ** 3)})

    # A proxy may only sit on the VM's LOWEST-numbered VIF, hence sorting by device above rather than
    # taking VIFs[0] — the list comes back in creation order, which is the same thing only by luck.
    proxy = x.PVS_proxy.create(site, vifs[0])

    print("Site '%s' with %d cache(s) and %d server(s)"
          % (x.PVS_site.get_name_label(site),
             len(x.PVS_site.get_cache_storage(site)),
             len(x.PVS_site.get_servers(site))))
    # "caching" means it is actually accelerating. A site with no cache storage reports
    # "initialised", and a proxy on a VM whose VIF is unplugged reports "stopped".
    print("  %s: %s" % (x.VM.get_name_label(vm), x.PVS_proxy.get_status(proxy)))

    # Forgetting the site only cascades its cache storage - a running proxy or a server it still
    # has makes forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down
    # ourselves first, in the same order every real PVS teardown uses.
    x.PVS_proxy.destroy(proxy)
    for server_ref in x.PVS_site.get_servers(site):
        x.PVS_server.forget(server_ref)
    x.PVS_site.forget(site)
    print("OK: configure-pvs-accelerator")
    session.logout()


def local_sr(x, host):
    """The host's own non-ISO storage, found through its PBDs."""
    for pbd in x.host.get_PBDs(host):
        sr = x.PBD.get_SR(pbd)
        record = x.SR.get_record(sr)
        if not record["shared"] and record["content_type"] != "iso" and record["type"] != "udev":
            return sr
    return None
```

<details><summary>Example output</summary>

```text
Site 'sdk-example-pvs' with 2 cache(s) and 1 server(s)
  db-01: stopped
OK: configure-pvs-accelerator
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/ConfigurePvsAccelerator.cs`](../../csharp/HostsAndPools/ConfigurePvsAccelerator.cs)

```csharp
/// <summary>
/// Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS server,
/// put a read cache on each host's local storage, accelerate a VM by proxying its first NIC, then forget
/// the site — which cascades to everything hanging off it.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigurePvsAccelerator("https://xenserver", "root", password, "db-01");
/// </code>
/// </example>
public static void ConfigurePvsAccelerator(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);

    // Check the VM first, before creating anything: it needs a NIC for the proxy to sit on, and one
    // that no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT). It need not be
    // running - a proxy on a halted VM just reports "stopped" until it starts.
    var vm = VmByName(session, vmName);
    var vifs = VM.get_VIFs(session, vm)
        .OrderBy(r => int.Parse(VIF.get_device(session, r))).ToList();
    if (vifs.Count == 0) throw new Exception($"{vmName} has no network interface to accelerate");
    foreach (var existing in PVS_proxy.get_all_records(session).Values)
        if (existing.VIF.Equals(vifs[0]))
            throw new Exception($"{vmName} is already accelerated by site " +
                                $"'{PVS_site.get_name_label(session, existing.site)}'");

    var site = PVS_site.introduce(session, "sdk-example-pvs", "Created by the SDK examples", "");
    PVS_server.introduce(session, new[] { "203.0.113.90" }, 6910, 6930, site);

    // The read cache should be on LOCAL storage. The point of the accelerator is to keep reads off
    // the network; the server does not enforce that, but a cache on shared storage rarely makes
    // sense and can't be shared between hosts anyway.
    foreach (var hostRef in Host.get_all(session))
    {
        var local = LocalSr(session, hostRef);
        if (local == null) continue;
        PVS_cache_storage.create(session, new PVS_cache_storage
        {
            host = hostRef,
            SR = local,
            site = site,
            size = 10L * 1024 * 1024 * 1024,
        });
    }

    // A proxy may only sit on the VM's LOWEST-numbered NIC, hence sorting by device above rather
    // than taking VIFs[0] — the list comes back in creation order, which is the same thing only by
    // luck.
    var proxy = PVS_proxy.create(session, site, vifs[0]);

    var record = PVS_site.get_record(session, site);
    Console.WriteLine($"Site '{record.name_label}' with {record.cache_storage.Count} cache(s) "
                      + $"and {record.servers.Count} server(s)");
    // "caching" means it is actually accelerating. A site with no cache storage reports
    // "initialised", and a proxy on a VM whose NIC is unplugged reports "stopped".
    Console.WriteLine($"  {VM.get_name_label(session, vm)}: {PVS_proxy.get_status(session, proxy)}");

    // Forgetting the site only cascades its cache storage - a running proxy or a server it still has
    // makes forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down
    // ourselves first, in the same order every real PVS teardown uses.
    PVS_proxy.destroy(session, proxy);
    foreach (var serverRef in PVS_site.get_servers(session, site)) PVS_server.forget(session, serverRef);
    PVS_site.forget(session, site);
    Console.WriteLine("OK: configure-pvs-accelerator");
    session.logout();
}

/// <summary>The host's own non-ISO storage, found through its PBDs.</summary>
private static XenRef<SR> LocalSr(Session session, XenRef<Host> host)
{
    foreach (var pbdRef in Host.get_PBDs(session, host))
    {
        // Keep the REF and read the record through it: a record fetched by get_record does not
        // carry its own opaque_ref, so reaching for sr.opaque_ref afterwards hands you a null.
        var srRef = PBD.get_SR(session, pbdRef);
        var sr = SR.get_record(session, srRef);
        if (!sr.shared && sr.content_type != "iso" && sr.type != "udev")
            return srRef;
    }
    return null;
}
```

<details><summary>Example output</summary>

```text
Site 'sdk-example-pvs' with 2 cache(s) and 1 server(s)
  db-01: stopped
OK: configure-pvs-accelerator
```

</details>

## Go

Source: [`go/configure_pvs_accelerator.go`](../../go/configure_pvs_accelerator.go)

```go
package main

import (
	"fmt"
	"sort"
	"strconv"

	"go/xenapi"
)

// configurePvsAccelerator - Configure PVS Accelerator.
//
// Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS
// server, put a read cache on each host's local storage, accelerate a VM by proxying its first NIC,
// then forget the site — which cascades to everything hanging off it.
func configurePvsAccelerator(url, user, password, vmName string) {
	session := connect(url, user, password)
	defer session.Logout()

	// Check the VM first, before creating anything: it needs a NIC for the proxy to sit on. It need
	// not be running - a proxy on a halted VM just reports "stopped" until it starts.
	vm := vmByName(session, vmName)
	vifs, err := xenapi.VM.GetVIFs(session, vm)
	check(err)
	if len(vifs) == 0 {
		panic(fmt.Sprintf("%s has no network interface to accelerate", vmName))
	}
	// A proxy may only sit on the VM's LOWEST-numbered NIC, so sort by device rather than taking
	// VIFs[0] — the list comes back in creation order, which is the same thing only by luck.
	sort.Slice(vifs, func(i, j int) bool { return vifDevice(session, vifs[i]) < vifDevice(session, vifs[j]) })
	// ... and one that no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT).
	proxies, err := xenapi.PVSProxy.GetAllRecords(session)
	check(err)
	for _, proxy := range proxies {
		if proxy.VIF == vifs[0] {
			siteName, _ := xenapi.PVSSite.GetNameLabel(session, proxy.Site)
			panic(fmt.Sprintf("%s is already accelerated by site '%s'", vmName, siteName))
		}
	}

	site, err := xenapi.PVSSite.Introduce(session, "sdk-example-pvs", "Created by the SDK examples", "")
	check(err)
	_, err = xenapi.PVSServer.Introduce(session, []string{"203.0.113.90"}, 6910, 6930, site)
	check(err)

	// The read cache should be on LOCAL storage. The point of the accelerator is to keep reads off the
	// network; the server does not enforce that, but a cache on shared storage rarely makes sense and
	// can't be shared between hosts anyway.
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	for _, host := range hosts {
		local, ok := localSR(session, host)
		if !ok {
			continue
		}
		_, err = xenapi.PVSCacheStorage.Create(session, xenapi.PVSCacheStorageRecord{
			Host: host, SR: local, Site: site, Size: 10 * 1024 * 1024 * 1024,
		})
		check(err)
	}

	// A proxy may only sit on the VM's LOWEST-numbered NIC, hence sorting by device above rather than
	// taking VIFs[0] — the list comes back in creation order, which is the same thing only by luck.
	proxy, err := xenapi.PVSProxy.Create(session, site, vifs[0])
	check(err)

	record, err := xenapi.PVSSite.GetRecord(session, site)
	check(err)
	fmt.Printf("Site '%s' with %d cache(s) and %d server(s)\n",
		record.NameLabel, len(record.CacheStorage), len(record.Servers))
	// "caching" means it is actually accelerating. A site with no cache storage reports "initialised",
	// and a proxy on a VM whose NIC is unplugged reports "stopped".
	status, err := xenapi.PVSProxy.GetStatus(session, proxy)
	check(err)
	vmLabel, _ := xenapi.VM.GetNameLabel(session, vm)
	fmt.Printf("  %s: %s\n", vmLabel, status)

	// Forgetting the site only cascades its cache storage - a running proxy or a server it still
	// has makes forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down
	// ourselves first, in the same order every real PVS teardown uses. (Cache storage doesn't need
	// a separate call - forget cascades it correctly.)
	check(xenapi.PVSProxy.Destroy(session, proxy))
	servers, err := xenapi.PVSSite.GetServers(session, site)
	check(err)
	for _, server := range servers {
		check(xenapi.PVSServer.Forget(session, server))
	}
	check(xenapi.PVSSite.Forget(session, site))
	fmt.Println("OK: configure-pvs-accelerator")
}

// localSR returns the host's own non-ISO storage, found through its PBDs.
func localSR(session *xenapi.Session, host xenapi.HostRef) (xenapi.SRRef, bool) {
	pbds, err := xenapi.Host.GetPBDs(session, host)
	check(err)
	for _, pbd := range pbds {
		ref, err := xenapi.PBD.GetSR(session, pbd)
		check(err)
		sr, err := xenapi.SR.GetRecord(session, ref)
		check(err)
		if !sr.Shared && sr.ContentType != "iso" && sr.Type != "udev" {
			return ref, true
		}
	}
	return "", false
}

func vifDevice(session *xenapi.Session, vif xenapi.VIFRef) int {
	device, err := xenapi.VIF.GetDevice(session, vif)
	check(err)
	n, _ := strconv.Atoi(device)
	return n
}
```

<details><summary>Example output</summary>

```text
Site 'sdk-example-pvs' with 2 cache(s) and 1 server(s)
  db-01: stopped
OK: configure-pvs-accelerator
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ConfigurePvsAccelerator.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ConfigurePvsAccelerator.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.PVSCacheStorage;
import com.xensource.xenapi.PVSProxy;
import com.xensource.xenapi.PVSServer;
import com.xensource.xenapi.PVSSite;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigurePvsAccelerator {
    private ConfigurePvsAccelerator() {
    }

    /**
     * Configure PVS Accelerator.
     *
     * <p>Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS
     * server, put a read cache on each host's local storage, accelerate a VM by proxying its first NIC,
     * then forget the site — which cascades to everything hanging off it.
     *
     * <p>Build a PVS Accelerator site from nothing: a site, a PVS server, a read cache on each host, and
     * one accelerated VM (vmName). Then take it all down again.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigurePvsAccelerator.run("https://xenserver", "root", password, "db-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Check the VM first, before creating anything: it needs a NIC for the proxy to sit on. It
            // need not be running - a proxy on a halted VM just reports "stopped" until it starts.
            VM vm = vmByName(conn, vmName);
            java.util.List<VIF> vifs = new java.util.ArrayList<>(vm.getVIFs(conn));
            vifs.sort(java.util.Comparator.comparingInt(v -> {
                try {
                    return Integer.parseInt(v.getDevice(conn));
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            }));
            if (vifs.isEmpty()) throw new RuntimeException(vmName + " has no network interface to accelerate");
            // ... and one that no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT).
            for (PVSProxy.Record proxy : PVSProxy.getAllRecords(conn).values())
                if (proxy.VIF.equals(vifs.get(0)))
                    throw new RuntimeException(vmName + " is already accelerated by site '"
                            + proxy.site.getNameLabel(conn) + "'");

            PVSSite site = PVSSite.introduce(conn, "sdk-example-pvs", "Created by the SDK examples", "");
            PVSServer.introduce(conn, new java.util.HashSet<>(java.util.Arrays.asList("203.0.113.90")),
                6910L, 6930L, site);

            // The read cache should be on LOCAL storage. The point of the accelerator is to keep reads off
            // the network; the server does not enforce that, but a cache on shared storage rarely makes
            // sense and can't be shared between hosts anyway.
            for (Host host : Host.getAll(conn)) {
                SR local = localSr(conn, host);
                if (local == null) continue;
                PVSCacheStorage.Record cache = new PVSCacheStorage.Record();
                cache.host = host;
                cache.SR = local;
                cache.site = site;
                cache.size = 10L * 1024 * 1024 * 1024;
                PVSCacheStorage.create(conn, cache);
            }

            // A proxy may only sit on the VM's LOWEST-numbered VIF, hence sorting by device above rather
            // than taking the first one — the set comes back unordered, so "the first one" means
            // nothing here.
            PVSProxy proxy = PVSProxy.create(conn, site, vifs.get(0));

            PVSSite.Record record = site.getRecord(conn);
            System.out.printf("Site '%s' with %d cache(s) and %d server(s)%n",
                record.nameLabel, record.cacheStorage.size(), record.servers.size());
            // "caching" means it is actually accelerating. A site with no cache storage reports
            // "initialised", and a proxy on a VM whose VIF is unplugged reports "stopped".
            System.out.printf("  %s: %s%n", vm.getNameLabel(conn), proxy.getStatus(conn));

            // Forgetting the site only cascades its cache storage - a running proxy or a server it still
            // has makes forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down
            // ourselves first, in the same order every real PVS teardown uses.
            proxy.destroy(conn);
            for (PVSServer server : site.getServers(conn)) server.forget(conn);
            site.forget(conn);
            System.out.println("OK: configure-pvs-accelerator");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * The host's own non-ISO storage, found through its PBDs.
     */
    private static SR localSr(Connection conn, Host host) throws Exception {
        for (PBD pbd : host.getPBDs(conn)) {
            SR sr = pbd.getSR(conn);
            SR.Record r = sr.getRecord(conn);
            if (!r.shared && !"iso".equals(r.contentType) && r.type != null && !r.type.equals("udev"))
                return sr;
        }
        return null;
    }
}
```

<details><summary>Example output</summary>

```text
Site 'sdk-example-pvs' with 2 cache(s) and 1 server(s)
  db-01: stopped
OK: configure-pvs-accelerator
```

</details>
