<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure dynamic memory

Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the ordering rule the four bounds must obey enforced.

Workflow `configure-dynamic-memory`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-ConfigureDynamicMemory.ps1`](../../powershell/VirtualMachines/Invoke-ConfigureDynamicMemory.ps1)

```powershell
function Invoke-ConfigureDynamicMemory {
    <#
    .SYNOPSIS
        Configure dynamic memory.
    .DESCRIPTION
        Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the
        ordering rule the four bounds must obey enforced.
    .EXAMPLE
        Invoke-ConfigureDynamicMemory -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.power_state -eq 'Halted'
    } | Select-Object -First 1
    Write-Host ("{0}: static {1}-{2}, dynamic {3}-{4}" -f $vm.name_label,
        (Format-Gib $vm.memory_static_min), (Format-Gib $vm.memory_static_max),
        (Format-Gib $vm.memory_dynamic_min), (Format-Gib $vm.memory_dynamic_max))

    # Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
    # static maximum for every supported guest (lower can make it unstable), and never below the static
    # floor, which is the least the guest can boot in.
    $floor = [Math]::Max($vm.memory_static_min, [long]($vm.memory_static_max * 3 / 4))
    $ceiling = $vm.memory_static_max
    # MemoryDynamicRange takes the pair as one array argument, so the two bounds are set together and
    # cannot momentarily cross each other.
    Set-XenVM -Ref $vm.opaque_ref -MemoryDynamicRange @($floor, $ceiling)
    $after = Get-XenVM -Ref $vm.opaque_ref
    Write-Host ("  dynamic range now {0}-{1}" -f
        (Format-Gib $after.memory_dynamic_min), (Format-Gib $after.memory_dynamic_max))

    # The ordering is enforced, not advisory: a range wider than the static bounds is refused rather
    # than quietly clamped.
    try {
        # Parentheses are load-bearing: PowerShell's comma operator binds TIGHTER than multiplication, so
        # @($floor, $ceiling * 2) is @($floor, $ceiling) repeated twice - a four-element array whose first
        # two values are the range we already set. The call then succeeds and proves nothing.
        Set-XenVM -Ref $vm.opaque_ref -MemoryDynamicRange @($floor, ($ceiling * 2)) -ErrorAction Stop
        Write-Host "  ERROR: an out-of-range maximum was accepted"
    }
    catch {
        Write-Host "  refused a dynamic_max above static_max: $($_.Exception.Message)"
    }

    Set-XenVM -Ref $vm.opaque_ref -MemoryDynamicRange @($vm.memory_dynamic_min, $vm.memory_dynamic_max)
    Write-Host "OK: configure-dynamic-memory"
    $session | Disconnect-XenServer
}

function Format-Gib {
    param([long]$Bytes)
    "{0:N1} GiB" -f ($Bytes / 1GB)
}
```

<details><summary>Example output</summary>

```text
db-01: static 0.5 GiB-4.0 GiB, dynamic 4.0 GiB-4.0 GiB
  dynamic range now 3.0 GiB-4.0 GiB
  refused a dynamic_max above static_max: The dynamic memory range violates constraint static_min <= dynamic_min <= dynamic_max <= static_max.
OK: configure-dynamic-memory
```

</details>

## xe CLI

Source: [`cli/virtual-machines/configure-dynamic-memory.sh`](../../cli/virtual-machines/configure-dynamic-memory.sh)

```bash
# Configure dynamic memory.
#
# Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the ordering
# rule the four bounds must obey enforced.
#
# Run it:
#   ./workflows.sh configure-dynamic-memory https://xenserver root "$password"

configure_dynamic_memory() {
    vm=$(nth_csv "$(xe vm-list power-state=halted --minimal)" 1)
    static_min=$(xe vm-param-get uuid=$vm param-name=memory-static-min)
    static_max=$(xe vm-param-get uuid=$vm param-name=memory-static-max)
    dyn_min=$(xe vm-param-get uuid=$vm param-name=memory-dynamic-min)
    dyn_max=$(xe vm-param-get uuid=$vm param-name=memory-dynamic-max)
    echo "$(xe vm-param-get uuid=$vm param-name=name-label): static $(gib $static_min)-$(gib $static_max), dynamic $(gib $dyn_min)-$(gib $dyn_max)"

    # Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
    # static maximum for every supported guest (lower can make it unstable), and never below the static
    # floor, which is the least the guest can boot in.
    floor=$((static_max * 3 / 4))
    [ "$floor" -lt "$static_min" ] && floor=$static_min
    xe vm-memory-dynamic-range-set uuid=$vm min=$floor max=$static_max
    echo "  dynamic range now $(gib $(xe vm-param-get uuid=$vm param-name=memory-dynamic-min))-$(gib $(xe vm-param-get uuid=$vm param-name=memory-dynamic-max))"

    # The ordering is enforced, not advisory: a range wider than the static bounds is refused rather than
    # quietly clamped.
    # Both streams: xe prints a XenAPI failure on stdout, so 2>/dev/null alone still shows it.
    if xe vm-memory-dynamic-range-set uuid=$vm min=$floor max=$((static_max * 2)) >/dev/null 2>&1; then
        echo "  ERROR: an out-of-range maximum was accepted"
    else
        echo "  refused a dynamic_max above static_max"
    fi

    xe vm-memory-dynamic-range-set uuid=$vm min=$dyn_min max=$dyn_max
    echo "OK: configure-dynamic-memory"
}

# Bytes as GiB to one decimal place, using shell arithmetic only - there is no floating point here, so
# the fraction is worked out from the remainder.
gib() {
    local bytes=$1 whole tenths
    whole=$((bytes / 1073741824))
    tenths=$(((bytes % 1073741824) * 10 / 1073741824))
    echo "${whole}.${tenths} GiB"
}
```

<details><summary>Example output</summary>

```text
db-01: static 0.5 GiB-4.0 GiB, dynamic 4.0 GiB-4.0 GiB
  dynamic range now 3.0 GiB-4.0 GiB
  refused a dynamic_max above static_max
OK: configure-dynamic-memory
```

</details>

## Python

Source: [`python/virtual_machines/configure_dynamic_memory.py`](../../python/virtual_machines/configure_dynamic_memory.py)

```python
"""Configure dynamic memory.

Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the
ordering rule the four bounds must obey enforced.
"""

import XenAPI

from connection import connect


def configure_dynamic_memory(url, username, password):
    """Give a VM a dynamic memory range, so the host can reclaim memory from it under
    pressure instead of the VM holding a fixed amount.

    The four bounds must stay ordered: static_min <= dynamic_min <= dynamic_max <=
    static_max. The dynamic pair is what ballooning moves between; the static pair is the
    hard limit and can only be changed while the VM is off."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = next(ref for ref, v in x.VM.get_all_records().items()
              if not v["is_a_template"] and not v["is_control_domain"]
              and not v["is_a_snapshot"] and v["power_state"] == "Halted")
    before = x.VM.get_record(vm)
    print("%s: static %s-%s, dynamic %s-%s"
          % (before["name_label"], gib(before["memory_static_min"]), gib(before["memory_static_max"]),
             gib(before["memory_dynamic_min"]), gib(before["memory_dynamic_max"])))

    # Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
    # static maximum for every supported guest (lower can make it unstable), and never below the static
    # floor, which is the least the guest can boot in.
    floor = max(int(before["memory_static_min"]), int(before["memory_static_max"]) * 3 // 4)
    ceiling = int(before["memory_static_max"])
    x.VM.set_memory_dynamic_range(vm, str(floor), str(ceiling))
    after = x.VM.get_record(vm)
    print("  dynamic range now %s-%s" % (gib(after["memory_dynamic_min"]), gib(after["memory_dynamic_max"])))

    # The ordering is enforced, not advisory: a range wider than the static bounds is
    # refused rather than quietly clamped.
    try:
        x.VM.set_memory_dynamic_range(vm, str(floor), str(ceiling * 2))
        print("  ERROR: an out-of-range maximum was accepted")
    except XenAPI.Failure as e:
        print("  refused a dynamic_max above static_max: %s" % e.details[0])

    # str() throughout: memory is a 64-bit byte count and the binding's transport cannot carry
    # an integer that large, so the API takes these as strings.
    x.VM.set_memory_dynamic_range(vm, str(before["memory_dynamic_min"]), str(before["memory_dynamic_max"]))
    print("OK: configure-dynamic-memory")
    session.logout()


def gib(value):
    return "%.1f GiB" % (int(value) / float(1024 ** 3))
```

<details><summary>Example output</summary>

```text
db-01: static 0.5 GiB-4.0 GiB, dynamic 4.0 GiB-4.0 GiB
  dynamic range now 3.0 GiB-4.0 GiB
  refused a dynamic_max above static_max: MEMORY_CONSTRAINT_VIOLATION_ORDER
OK: configure-dynamic-memory
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/ConfigureDynamicMemory.cs`](../../csharp/VirtualMachines/ConfigureDynamicMemory.cs)

```csharp
/// <summary>
/// Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the
/// ordering rule the four bounds must obey enforced.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureDynamicMemory("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ConfigureDynamicMemory(string url, string user, string password)
{
    var session = Connect(url, user, password);

    var vm = VM.get_all_records(session).First(kv =>
        !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot &&
        kv.Value.power_state == vm_power_state.Halted);
    var before = vm.Value;
    Console.WriteLine($"{before.name_label}: static {Gib(before.memory_static_min)}-"
                      + $"{Gib(before.memory_static_max)}, dynamic {Gib(before.memory_dynamic_min)}-"
                      + $"{Gib(before.memory_dynamic_max)}");

    // Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
    // static maximum for every supported guest (lower can make it unstable), and never below the static
    // floor, which is the least the guest can boot in.
    var floor = Math.Max(before.memory_static_min, before.memory_static_max * 3 / 4);
    var ceiling = before.memory_static_max;
    VM.set_memory_dynamic_range(session, vm.Key.opaque_ref, floor, ceiling);
    Console.WriteLine($"  dynamic range now {Gib(VM.get_memory_dynamic_min(session, vm.Key.opaque_ref))}-"
                      + $"{Gib(VM.get_memory_dynamic_max(session, vm.Key.opaque_ref))}");

    // The ordering is enforced, not advisory: a range wider than the static bounds is refused rather
    // than quietly clamped.
    try
    {
        VM.set_memory_dynamic_range(session, vm.Key.opaque_ref, floor, ceiling * 2);
        Console.WriteLine("  ERROR: an out-of-range maximum was accepted");
    }
    catch (Failure failure)
    {
        Console.WriteLine($"  refused a dynamic_max above static_max: {failure.ErrorDescription[0]}");
    }

    VM.set_memory_dynamic_range(session, vm.Key.opaque_ref,
        before.memory_dynamic_min, before.memory_dynamic_max);
    Console.WriteLine("OK: configure-dynamic-memory");
    session.logout();
}

private static string Gib(long bytes) => $"{bytes / (1024.0 * 1024 * 1024):F1} GiB";
```

<details><summary>Example output</summary>

```text
db-01: static 0.5 GiB-4.0 GiB, dynamic 4.0 GiB-4.0 GiB
  dynamic range now 3.0 GiB-4.0 GiB
  refused a dynamic_max above static_max: MEMORY_CONSTRAINT_VIOLATION_ORDER
OK: configure-dynamic-memory
```

</details>

## Go

Source: [`go/configure_dynamic_memory.go`](../../go/configure_dynamic_memory.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// configureDynamicMemory - Configure dynamic memory.
//
// Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see
// the ordering rule the four bounds must obey enforced.
func configureDynamicMemory(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vm xenapi.VMRef
	var before xenapi.VMRecord
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && !v.IsASnapshot &&
			v.PowerState == xenapi.VMPowerStateHalted {
			vm, before = ref, v
			break
		}
	}
	fmt.Printf("%s: static %s-%s, dynamic %s-%s\n", before.NameLabel,
		gib(before.MemoryStaticMin), gib(before.MemoryStaticMax),
		gib(before.MemoryDynamicMin), gib(before.MemoryDynamicMax))

	// Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
	// static maximum for every supported guest (lower can make it unstable), and never below the static
	// floor, which is the least the guest can boot in.
	floor := before.MemoryStaticMax * 3 / 4
	if before.MemoryStaticMin > floor {
		floor = before.MemoryStaticMin
	}
	ceiling := before.MemoryStaticMax
	check(xenapi.VM.SetMemoryDynamicRange(session, vm, floor, ceiling))
	low, err := xenapi.VM.GetMemoryDynamicMin(session, vm)
	check(err)
	high, err := xenapi.VM.GetMemoryDynamicMax(session, vm)
	check(err)
	fmt.Printf("  dynamic range now %s-%s\n", gib(low), gib(high))

	// The ordering is enforced, not advisory: a range wider than the static bounds is refused rather than
	// quietly clamped.
	if err := xenapi.VM.SetMemoryDynamicRange(session, vm, floor, ceiling*2); err == nil {
		fmt.Println("  ERROR: an out-of-range maximum was accepted")
	} else {
		fmt.Printf("  refused a dynamic_max above static_max: %s\n", failureCode(err))
	}

	check(xenapi.VM.SetMemoryDynamicRange(session, vm, before.MemoryDynamicMin, before.MemoryDynamicMax))
	fmt.Println("OK: configure-dynamic-memory")
}

func gib(size int64) string {
	return fmt.Sprintf("%.1f GiB", float64(size)/(1024*1024*1024))
}
```

<details><summary>Example output</summary>

```text
secure-01: static 0.5 GiB-4.0 GiB, dynamic 4.0 GiB-4.0 GiB
  dynamic range now 3.0 GiB-4.0 GiB
  refused a dynamic_max above static_max: MEMORY_CONSTRAINT_VIOLATION_ORDER
OK: configure-dynamic-memory
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/ConfigureDynamicMemory.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/ConfigureDynamicMemory.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureDynamicMemory {
    private ConfigureDynamicMemory() {
    }

    /**
     * Configure dynamic memory.
     *
     * <p>Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see
     * the ordering rule the four bounds must obey enforced.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureDynamicMemory.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = null;
            VM.Record before = null;
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record v = e.getValue();
                if (!v.isATemplate && !v.isControlDomain && !v.isASnapshot
                        && v.powerState == Types.VmPowerState.HALTED) {
                    vm = e.getKey(); before = v; break;
                }
            }
            if (vm == null) throw new Exception("no halted VM");
            System.out.printf("%s: static %s-%s, dynamic %s-%s%n", before.nameLabel,
                    gib(before.memoryStaticMin), gib(before.memoryStaticMax),
                    gib(before.memoryDynamicMin), gib(before.memoryDynamicMax));

            // Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
            // static maximum for every supported guest (lower can make it unstable), and never below the static
            // floor, which is the least the guest can boot in.
            long floor = Math.max(before.memoryStaticMin, before.memoryStaticMax * 3 / 4);
            long ceiling = before.memoryStaticMax;
            vm.setMemoryDynamicRange(conn, floor, ceiling);
            System.out.printf("  dynamic range now %s-%s%n",
                    gib(vm.getMemoryDynamicMin(conn)), gib(vm.getMemoryDynamicMax(conn)));

            // The ordering is enforced, not advisory: a range wider than the static bounds is refused
            // rather than quietly clamped.
            try {
                vm.setMemoryDynamicRange(conn, floor, ceiling * 2);
                System.out.println("  ERROR: an out-of-range maximum was accepted");
            } catch (Types.XenAPIException e) {
                System.out.println("  refused a dynamic_max above static_max: " + e.shortDescription);
            }

            vm.setMemoryDynamicRange(conn, before.memoryDynamicMin, before.memoryDynamicMax);
            System.out.println("OK: configure-dynamic-memory");
        } finally {
            Session.logout(conn);
        }
    }

    private static String gib(long bytes) {
        return String.format("%.1f GiB", bytes / (1024.0 * 1024 * 1024));
    }
}
```

<details><summary>Example output</summary>

```text
db-01: static 0.5 GiB-4.0 GiB, dynamic 4.0 GiB-4.0 GiB
  dynamic range now 3.0 GiB-4.0 GiB
  refused a dynamic_max above static_max: The dynamic memory range violates constraint static_min &lt;= dynamic_min &lt;= dynamic_max &lt;= static_max.
OK: configure-dynamic-memory
```

</details>
