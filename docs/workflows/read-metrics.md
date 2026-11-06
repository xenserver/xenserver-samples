<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Read host & VM metrics

Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).

Workflow `read-metrics`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ReadMetrics.ps1`](../../powershell/HostsAndPools/Invoke-ReadMetrics.ps1)

```powershell
function Invoke-ReadMetrics {
    <#
    .SYNOPSIS
        Read host & VM metrics.
    .DESCRIPTION
        Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
    .EXAMPLE
        Invoke-ReadMetrics -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $hm = Get-XenHostMetrics -Ref $xenHost.metrics
    Write-Host ("Host $($xenHost.name_label): " +
        "$([long]($hm.memory_total / 1MB)) MiB total, " +
        "$([long](($xenHost | Invoke-XenHost -XenAction ComputeFreeMemory -PassThru) / 1MB)) MiB free, " +
        "live = $($hm.live)")

    $vm = Get-XenVM |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and $_.power_state -eq 'Running' } |
        Select-Object -First 1
    $vmm = Get-XenVMMetrics -Ref $vm.metrics
    Write-Host ("VM $($vm.name_label): " +
        "$($vmm.VCPUs_number) vCPU(s), $([long]($vmm.memory_actual / 1MB)) MiB")
    Write-Host "OK: read-metrics"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Host sdk-host1: 65536 MiB total, 57344 MiB free, live = True
VM web-01: 2 vCPU(s), 4096 MiB
OK: read-metrics
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/read-metrics.sh`](../../cli/hosts-and-pools/read-metrics.sh)

```bash
# Read host & VM metrics.
#
# Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
#
# Run it:
#   ./workflows.sh read-metrics https://xenserver root "$password"

read_metrics() {
    h=$(first_host)
    # On the CLI, a host's and a VM's metrics read as parameters of the host and VM themselves.
    echo "Host $(xe host-param-get uuid=$h param-name=name-label): free memory $(xe host-compute-free-memory uuid=$h), live=$(xe host-param-get uuid=$h param-name=host-metrics-live)"
    vm=$(vm_uuid web-01)
    echo "VM web-01: $(xe vm-param-get uuid=$vm param-name=VCPUs-number) vCPU(s)"
    echo "OK: read-metrics"
}
```

<details><summary>Example output</summary>

```text
Host sdk-host1: free memory , live=true
VM web-01: 2 vCPU(s)
OK: read-metrics
```

</details>

## Python

Source: [`python/hosts_and_pools/read_metrics.py`](../../python/hosts_and_pools/read_metrics.py)

```python
"""Read host & VM metrics.

Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).

Run it::

    read_metrics("https://xenserver", "root", password)
"""

from connection import connect


def read_metrics(url, username, password):
    """Read live capacity metrics off a host and a running VM (Host_metrics / VM_metrics)."""
    MIB = 1024 * 1024
    session = connect(url, username, password)
    host_ref, host = next(iter(session.xenapi.host.get_all_records().items()))
    hm = session.xenapi.host.get_metrics(host_ref)
    print("Host %s: %d MiB total, %d MiB free, live = %s"
          % (host["name_label"],
             int(session.xenapi.host_metrics.get_memory_total(hm)) // MIB,
             int(session.xenapi.host.compute_free_memory(host_ref)) // MIB,
             session.xenapi.host_metrics.get_live(hm)))

    vm = next(ref for ref, r in session.xenapi.VM.get_all_records().items()
              if not r["is_a_template"] and not r["is_control_domain"]
              and r["power_state"] == "Running")
    vmm = session.xenapi.VM.get_metrics(vm)
    print("VM %s: %s vCPU(s), %d MiB"
          % (session.xenapi.VM.get_name_label(vm),
             session.xenapi.VM_metrics.get_VCPUs_number(vmm),
             int(session.xenapi.VM_metrics.get_memory_actual(vmm)) // MIB))
    print("OK: read-metrics")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Host sdk-host1: 65536 MiB total, 57344 MiB free, live = True
VM web-01: 2 vCPU(s), 4096 MiB
OK: read-metrics
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/ReadMetrics.cs`](../../csharp/HostsAndPools/ReadMetrics.cs)

```csharp
/// <summary>
/// Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
/// </summary>
/// <example>
/// <code>
/// Workflows.ReadMetrics("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ReadMetrics(string url, string user, string password)
{
    const long MiB = 1024L * 1024;
    var session = Connect(url, user, password);
    var (hostRef, host) = Host.get_all_records(session).First();
    var hm = Host.get_metrics(session, hostRef);
    Console.WriteLine($"Host {host.name_label}: " +
        $"{Host_metrics.get_memory_total(session, hm) / MiB} MiB total, " +
        $"{Host.compute_free_memory(session, hostRef) / MiB} MiB free, " +
        $"live = {Host_metrics.get_live(session, hm)}");

    var vm = VM.get_all_records(session).First(kv => !kv.Value.is_a_template
        && !kv.Value.is_control_domain && kv.Value.power_state == vm_power_state.Running).Key;
    var vmm = VM.get_metrics(session, vm);
    Console.WriteLine($"VM {VM.get_name_label(session, vm)}: " +
        $"{VM_metrics.get_VCPUs_number(session, vmm)} vCPU(s), " +
        $"{VM_metrics.get_memory_actual(session, vmm) / MiB} MiB");
    Console.WriteLine("OK: read-metrics");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Host sdk-host1: 65536 MiB total, 57344 MiB free, live = True
VM web-01: 2 vCPU(s), 4096 MiB
OK: read-metrics
```

</details>

## Go

Source: [`go/read_metrics.go`](../../go/read_metrics.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// readMetrics - Read host & VM metrics.
//
// Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
//
// Run it:
//
//	readMetrics("https://xenserver", "root", password)
func readMetrics(url, user, password string) {
	const MiB = 1024 * 1024

	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var hostRef xenapi.HostRef
	var hostName string
	for ref, h := range hosts {
		hostRef, hostName = ref, h.NameLabel
		break
	}
	hm, err := xenapi.Host.GetMetrics(session, hostRef)
	check(err)
	total, _ := xenapi.HostMetrics.GetMemoryTotal(session, hm)
	free, _ := xenapi.Host.ComputeFreeMemory(session, hostRef)
	live, _ := xenapi.HostMetrics.GetLive(session, hm)
	fmt.Printf("Host %s: %d MiB total, %d MiB free, live = %v\n",
		hostName, total/MiB, free/MiB, live)

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vmRef xenapi.VMRef
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && v.PowerState == xenapi.VMPowerStateRunning {
			vmRef = ref
			break
		}
	}
	vmm, err := xenapi.VM.GetMetrics(session, vmRef)
	check(err)
	vcpus, _ := xenapi.VMMetrics.GetVCPUsNumber(session, vmm)
	mem, _ := xenapi.VMMetrics.GetMemoryActual(session, vmm)
	name, _ := xenapi.VM.GetNameLabel(session, vmRef)
	fmt.Printf("VM %s: %d vCPU(s), %d MiB\n", name, vcpus, mem/MiB)
	fmt.Println("OK: read-metrics")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Host sdk-host1: 65536 MiB total, 57344 MiB free, live = true
VM cache-01: 2 vCPU(s), 4096 MiB
OK: read-metrics
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ReadMetrics.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ReadMetrics.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.HostMetrics;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VMMetrics;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ReadMetrics {
    private ReadMetrics() {
    }

    /**
     * Read host &amp; VM metrics.
     *
     * <p>Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ReadMetrics.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        final long MiB = 1024L * 1024;
        Connection conn = connect(url, user, password);
        Map.Entry<Host, Host.Record> he = Host.getAllRecords(conn).entrySet().iterator().next();
        HostMetrics hm = he.getKey().getMetrics(conn);
        System.out.println("Host " + he.getValue().nameLabel + ": "
                + hm.getMemoryTotal(conn) / MiB + " MiB total, "
                + he.getKey().computeFreeMemory(conn) / MiB + " MiB free, "
                + "live = " + hm.getLive(conn));

        VM vm = null;
        for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
            VM.Record r = e.getValue();
            if (!r.isATemplate && !r.isControlDomain && r.powerState == Types.VmPowerState.RUNNING) {
                vm = e.getKey();
                break;
            }
        }
        VMMetrics vmm = vm.getMetrics(conn);
        System.out.println("VM " + vm.getNameLabel(conn) + ": "
                + vmm.getVCPUsNumber(conn) + " vCPU(s), "
                + vmm.getMemoryActual(conn) / MiB + " MiB");
        System.out.println("OK: read-metrics");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Host sdk-host1: 65536 MiB total, 57344 MiB free, live = true
VM web-01: 2 vCPU(s), 4096 MiB
OK: read-metrics
```

</details>
