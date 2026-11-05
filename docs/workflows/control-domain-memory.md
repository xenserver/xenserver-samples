<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Change control domain memory

Read and change a host's control domain (dom0) memory, then put it back. One setter pins the static and dynamic bounds together, because dom0 does not balloon.

Workflow `control-domain-memory`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/ControlDomainMemory.cs`](../../csharp/HostsAndPools/ControlDomainMemory.cs)

```csharp
/// <summary>
/// Read and change a host's control domain (dom0) memory, then put it back. One setter pins the static
/// and dynamic bounds together, because dom0 does not balloon.
/// </summary>
/// <example>
/// <code>
/// Workflows.ControlDomainMemory("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ControlDomainMemory(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var host = Host.get_all(session)[0];
    var dom0 = Host.get_resident_VMs(session, host.opaque_ref)
        .First(vm => VM.get_is_control_domain(session, vm.opaque_ref));

    var original = VM.get_memory_dynamic_min(session, dom0.opaque_ref);
    Console.WriteLine($"{Host.get_name_label(session, host.opaque_ref)} dom0: "
                      + $"{original / (double)(1024 * 1024 * 1024):F1} GiB");

    // One setter, not a range: dom0 does not balloon, so set_memory pins the static and dynamic
    // bounds and the target together. The new size takes effect at the next reboot, so change
    // it with the host in maintenance mode — the API itself does not stop you.
    VM.set_memory(session, dom0.opaque_ref, original + 1024L * 1024 * 1024);
    var record = VM.get_record(session, dom0.opaque_ref);
    Console.WriteLine($"  now {record.memory_dynamic_min / (double)(1024 * 1024 * 1024):F1} GiB "
                      + $"(static {record.memory_static_min}-{record.memory_static_max}, "
                      + $"dynamic {record.memory_dynamic_min}-{record.memory_dynamic_max})");

    VM.set_memory(session, dom0.opaque_ref, original);   // leave the pool as we found it
    Console.WriteLine("OK: control-domain-memory");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
sdk-host1 dom0: 2.0 GiB
  now 3.0 GiB (static 2147483648-3221225472, dynamic 3221225472-3221225472)
OK: control-domain-memory
```

</details>

## Python

Source: [`python/hosts_and_pools/control_domain_memory.py`](../../python/hosts_and_pools/control_domain_memory.py)

```python
"""Change control domain memory.

Read and change a host's control domain (dom0) memory, then put it back. One setter pins the static
and dynamic bounds together, because dom0 does not balloon.

Run it::

    control_domain_memory("https://xenserver", "root", password)
"""

from connection import connect


def control_domain_memory(url, username, password):
    """Read and change a host's control domain (dom0) memory.

    VM.set_memory is a single-value setter: it pins the static and dynamic bounds and the
    target together, which is what dom0 needs — it does not balloon. The new size takes
    effect when the host next reboots, so change it with the host in maintenance mode; the API
    itself does not stop you."""
    session = connect(url, username, password)
    x = session.xenapi

    host = x.host.get_all()[0]
    dom0 = next(vm for vm in x.host.get_resident_VMs(host) if x.VM.get_is_control_domain(vm))
    original = int(x.VM.get_memory_dynamic_min(dom0))
    print("%s dom0: %.1f GiB" % (x.host.get_name_label(host), original / float(1024 ** 3)))

    x.VM.set_memory(dom0, str(original + 1024 ** 3))
    record = x.VM.get_record(dom0)
    print("  now %.1f GiB (static %s-%s, dynamic %s-%s)"
          % (int(record["memory_dynamic_min"]) / float(1024 ** 3),
             record["memory_static_min"], record["memory_static_max"],
             record["memory_dynamic_min"], record["memory_dynamic_max"]))

    x.VM.set_memory(dom0, str(original))     # leave the pool as we found it
    print("OK: control-domain-memory")
    session.logout()
```

<details><summary>Example output</summary>

```text
sdk-host1 dom0: 2.0 GiB
  now 3.0 GiB (static 2147483648-3221225472, dynamic 3221225472-3221225472)
OK: control-domain-memory
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ControlDomainMemory.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ControlDomainMemory.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.PoolConnection.connect;

public final class ControlDomainMemory {
    private ControlDomainMemory() {
    }

    /**
     * Change control domain memory.
     *
     * <p>Read and change a host's control domain (dom0) memory, then put it back. One setter pins the
     * static and dynamic bounds together, because dom0 does not balloon.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ControlDomainMemory.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Host host = Host.getAll(conn).iterator().next();
            VM dom0 = null;
            for (VM vm : host.getResidentVMs(conn))
                if (vm.getIsControlDomain(conn)) { dom0 = vm; break; }
            if (dom0 == null) throw new Exception("the host reports no control domain");

            long original = dom0.getMemoryDynamicMin(conn);
            System.out.printf("%s dom0: %.1f GiB%n", host.getNameLabel(conn),
                original / (double) (1024L * 1024 * 1024));

            // One setter, not a range: dom0 does not balloon, so setMemory pins the static and dynamic
            // bounds and the target together. The new size takes effect at the next reboot, so change
            // it with the host in maintenance mode — the API itself does not stop you.
            dom0.setMemory(conn, original + 1024L * 1024 * 1024);
            VM.Record record = dom0.getRecord(conn);
            System.out.printf("  now %.1f GiB (static %d-%d, dynamic %d-%d)%n",
                record.memoryDynamicMin / (double) (1024L * 1024 * 1024),
                record.memoryStaticMin, record.memoryStaticMax,
                record.memoryDynamicMin, record.memoryDynamicMax);

            dom0.setMemory(conn, original);   // leave the pool as we found it
            System.out.println("OK: control-domain-memory");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
sdk-host2 dom0: 2.0 GiB
  now 3.0 GiB (static 2147483648-3221225472, dynamic 3221225472-3221225472)
OK: control-domain-memory
```

</details>

## Go

Source: [`go/control_domain_memory.go`](../../go/control_domain_memory.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// controlDomainMemory - Change control domain memory.
//
// Read and change a host's control domain (dom0) memory, then put it back. One setter pins the
// static and dynamic bounds together, because dom0 does not balloon.
func controlDomainMemory(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	dom0, ok := controlDomainOf(session, hosts[0])
	if !ok {
		panic("the host reports no control domain")
	}

	original, err := xenapi.VM.GetMemoryDynamicMin(session, dom0)
	check(err)
	name, _ := xenapi.Host.GetNameLabel(session, hosts[0])
	fmt.Printf("%s dom0: %.1f GiB\n", name, float64(original)/(1024*1024*1024))

	// One setter, not a range: dom0 does not balloon, so SetMemory pins the static and dynamic bounds
	// and the target together. The new size takes effect at the next reboot, so change it with the
	// host in maintenance mode — the API itself does not stop you.
	check(xenapi.VM.SetMemory(session, dom0, original+1024*1024*1024))
	record, err := xenapi.VM.GetRecord(session, dom0)
	check(err)
	fmt.Printf("  now %.1f GiB (static %d-%d, dynamic %d-%d)\n",
		float64(record.MemoryDynamicMin)/(1024*1024*1024),
		record.MemoryStaticMin, record.MemoryStaticMax,
		record.MemoryDynamicMin, record.MemoryDynamicMax)

	check(xenapi.VM.SetMemory(session, dom0, original)) // leave the pool as we found it
	fmt.Println("OK: control-domain-memory")
}

func controlDomainOf(session *xenapi.Session, host xenapi.HostRef) (xenapi.VMRef, bool) {
	vms, err := xenapi.Host.GetResidentVMs(session, host)
	check(err)
	for _, vm := range vms {
		isDom0, err := xenapi.VM.GetIsControlDomain(session, vm)
		check(err)
		if isDom0 {
			return vm, true
		}
	}
	return "", false
}
```

<details><summary>Example output</summary>

```text
sdk-host1 dom0: 2.0 GiB
  now 3.0 GiB (static 2147483648-3221225472, dynamic 3221225472-3221225472)
OK: control-domain-memory
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ControlDomainMemory.ps1`](../../powershell/HostsAndPools/Invoke-ControlDomainMemory.ps1)

```powershell
function Invoke-ControlDomainMemory {
    <#
    .SYNOPSIS
        Change control domain memory.
    .DESCRIPTION
        Read and change a host's control domain (dom0) memory, then put it back. One setter pins the static
        and dynamic bounds together, because dom0 does not balloon.
    .EXAMPLE
        Invoke-ControlDomainMemory -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $xenHost = Get-XenHost | Select-Object -First 1
    # dom0 is a VM like any other, found among the host's resident VMs.
    $dom0 = $xenHost.resident_VMs | ForEach-Object { Get-XenVM -Ref $_.opaque_ref } |
        Where-Object { $_.is_control_domain } | Select-Object -First 1
    $original = [long]$dom0.memory_dynamic_min
    Write-Host ("$($xenHost.name_label) dom0: {0:N1} GiB" -f ($original / 1GB))

    # -Memory, not -MemoryDynamicRange: dom0 does not balloon, so this one setter pins the static and
    # dynamic bounds and the target together. The new size takes effect at the next reboot, so change
    # it with the host in maintenance mode — the API itself does not stop you.
    Set-XenVM -VM $dom0 -Memory ($original + 1GB)
    $updated = Get-XenVM -Ref $dom0.opaque_ref
    Write-Host ("  now {0:N1} GiB (static {1}-{2}, dynamic {3}-{4})" -f
        ($updated.memory_dynamic_min / 1GB), $updated.memory_static_min, $updated.memory_static_max,
        $updated.memory_dynamic_min, $updated.memory_dynamic_max)

    Set-XenVM -VM $dom0 -Memory $original   # leave the pool as we found it
    Write-Host "OK: control-domain-memory"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
sdk-host1 dom0: 2.0 GiB
  now 3.0 GiB (static 2147483648-3221225472, dynamic 3221225472-3221225472)
OK: control-domain-memory
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/control-domain-memory.sh`](../../cli/hosts-and-pools/control-domain-memory.sh)

```bash
# Change control domain memory.
#
# Read and change a host's control domain (dom0) memory, then put it back. One setter pins the static and
# dynamic bounds together, because dom0 does not balloon.
#
# Run it:
#   ./workflows.sh control-domain-memory https://xenserver root "$password"

control_domain_memory() {
    h=$(nth_csv "$(xe host-list --minimal)" 1)
    # dom0 is a VM like any other, and vm-list includes it: one control domain per host.
    dom0=$(first_csv "$(xe vm-list is-control-domain=true resident-on=$h --minimal)")
    [ -n "$dom0" ] || { echo "the host reports no control domain" >&2; return 1; }
    original=$(xe vm-param-get uuid=$dom0 param-name=memory-dynamic-min)
    echo "$(xe host-param-get uuid=$h param-name=name-label) dom0: $((original / 1024 / 1024 / 1024)) GiB"

    # vm-memory-set, not vm-memory-limits-set: dom0 does not balloon, so one value pins the static and
    # dynamic bounds and the target together. It takes effect at the host's next reboot.
    xe vm-memory-set uuid=$dom0 memory=$((original + 1073741824))
    echo "  now $(( $(xe vm-param-get uuid=$dom0 param-name=memory-dynamic-min) / 1024 / 1024 / 1024 )) GiB (static $(xe vm-param-get uuid=$dom0 param-name=memory-static-min)-$(xe vm-param-get uuid=$dom0 param-name=memory-static-max), dynamic $(xe vm-param-get uuid=$dom0 param-name=memory-dynamic-min)-$(xe vm-param-get uuid=$dom0 param-name=memory-dynamic-max))"

    xe vm-memory-set uuid=$dom0 memory=$original    # leave the pool as we found it
    echo "OK: control-domain-memory"
}
```

<details><summary>Example output</summary>

```text
sdk-host1 dom0: 2 GiB
  now 3 GiB (static 2147483648-3221225472, dynamic 3221225472-3221225472)
OK: control-domain-memory
```

</details>
