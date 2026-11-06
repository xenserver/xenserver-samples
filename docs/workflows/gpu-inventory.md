<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# GPU inventory

Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.

Workflow `gpu-inventory`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-GpuInventory.ps1`](../../powershell/HostsAndPools/Invoke-GpuInventory.ps1)

```powershell
function Invoke-GpuInventory {
    <#
    .SYNOPSIS
        GPU inventory.
    .DESCRIPTION
        Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.
    .EXAMPLE
        Invoke-GpuInventory -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $groups = Get-XenGPUGroup
    Write-Host "GPU groups ($(@($groups).Count)):"
    foreach ($group in $groups) {
        $types = $group.supported_VGPU_types | ForEach-Object { (Get-XenVGPUType -Ref $_).model_name }
        Write-Host "  - $($group.name_label): $(@($group.PGPUs).Count) pGPU(s), vGPU types: $($types -join ', ')"
    }
    # How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU full
    # before using the next, breadth-first spreads them out.
    $group = $groups | Select-Object -First 1
    $before = $group.allocation_algorithm
    $group | Set-XenGPUGroup -AllocationAlgorithm breadth_first
    $after = (Get-XenGPUGroup -Ref $group.opaque_ref).allocation_algorithm
    Write-Host "Allocation:      $before -> $after"
    $group | Set-XenGPUGroup -AllocationAlgorithm $before
    Write-Host "OK: gpu-inventory"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
GPU groups (2):
  - Group of NVIDIA GRID K1: 1 pGPU(s), vGPU types: passthrough, GRID K100
  - Group of NVIDIA GRID K1: 1 pGPU(s), vGPU types: passthrough, GRID K100
Allocation:      depth_first -> breadth_first
OK: gpu-inventory
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/gpu-inventory.sh`](../../cli/hosts-and-pools/gpu-inventory.sh)

```bash
# GPU inventory.
#
# Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.
#
# Run it:
#   ./workflows.sh gpu-inventory https://xenserver root "$password"

gpu_inventory() {
    echo "GPU groups:"
    groups=$(xe gpu-group-list --minimal)
    for g in ${groups//,/ }; do
        vtypes=$(set_to_csv "$(xe gpu-group-param-get uuid=$g param-name=supported-VGPU-types)")
        models=""
        for t in ${vtypes//,/ }; do models="$models $(xe vgpu-type-param-get uuid=$t param-name=model-name)"; done
        echo "  - $(xe gpu-group-param-get uuid=$g param-name=name-label): vGPU types:$models"
    done

    # How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU
    # full before using the next, breadth-first spreads them out.
    group=$(first_csv "$groups")
    before=$(xe gpu-group-param-get uuid=$group param-name=allocation-algorithm)
    xe gpu-group-param-set uuid=$group allocation-algorithm=breadth-first
    echo "Allocation:      $before -> $(xe gpu-group-param-get uuid=$group param-name=allocation-algorithm)"
    xe gpu-group-param-set uuid=$group allocation-algorithm=$before
    echo "OK: gpu-inventory"
}
```

<details><summary>Example output</summary>

```text
GPU groups:
  - Group of NVIDIA GRID K1: vGPU types: passthrough GRID K100
  - Group of NVIDIA GRID K1: vGPU types: passthrough GRID K100
Allocation:      depth-first -> breadth-first
OK: gpu-inventory
```

</details>

## Python

Source: [`python/hosts_and_pools/gpu_inventory.py`](../../python/hosts_and_pools/gpu_inventory.py)

```python
"""GPU inventory.

Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.

Run it::

    gpu_inventory("https://xenserver", "root", password)
"""

from connection import connect


def gpu_inventory(url, username, password):
    """Take an inventory of the pool's GPU groups: their pGPUs and the vGPU types they support."""
    session = connect(url, username, password)
    groups = session.xenapi.GPU_group.get_all_records()
    print("GPU groups (%d):" % len(groups))
    for group in groups.values():
        types = [session.xenapi.VGPU_type.get_model_name(t) for t in group["supported_VGPU_types"]]
        print("  - %s: %d pGPU(s), vGPU types: %s"
              % (group["name_label"], len(group["PGPUs"]), ", ".join(types)))
    # How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU
    # full before using the next, breadth-first spreads them out.
    group_ref = list(groups.keys())[0]
    before = session.xenapi.GPU_group.get_allocation_algorithm(group_ref)
    session.xenapi.GPU_group.set_allocation_algorithm(group_ref, "breadth_first")
    print("Allocation:      %s -> %s"
          % (before, session.xenapi.GPU_group.get_allocation_algorithm(group_ref)))
    session.xenapi.GPU_group.set_allocation_algorithm(group_ref, before)
    print("OK: gpu-inventory")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
GPU groups (2):
  - Group of NVIDIA GRID K1: 1 pGPU(s), vGPU types: passthrough, GRID K100
  - Group of NVIDIA GRID K1: 1 pGPU(s), vGPU types: passthrough, GRID K100
Allocation:      depth_first -> breadth_first
OK: gpu-inventory
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/GpuInventory.cs`](../../csharp/HostsAndPools/GpuInventory.cs)

```csharp
/// <summary>
/// Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.
/// </summary>
/// <example>
/// <code>
/// Workflows.GpuInventory("https://xenserver", "root", password);
/// </code>
/// </example>
public static void GpuInventory(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var groups = GPU_group.get_all_records(session);
    Console.WriteLine($"GPU groups ({groups.Count}):");
    foreach (var group in groups.Values)
    {
        var types = group.supported_VGPU_types
            .Select(t => VGPU_type.get_model_name(session, t.opaque_ref));
        Console.WriteLine($"  - {group.name_label}: {group.PGPUs.Count} pGPU(s), " +
            $"vGPU types: {string.Join(", ", types)}");
    }
    // How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU
    // full before using the next, breadth-first spreads them out.
    var groupRef = groups.Keys.First().opaque_ref;
    var beforeAlloc = GPU_group.get_allocation_algorithm(session, groupRef);
    GPU_group.set_allocation_algorithm(session, groupRef, allocation_algorithm.breadth_first);
    Console.WriteLine($"Allocation:      {beforeAlloc} -> {GPU_group.get_allocation_algorithm(session, groupRef)}");
    GPU_group.set_allocation_algorithm(session, groupRef, beforeAlloc);
    Console.WriteLine("OK: gpu-inventory");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
GPU groups (2):
  - Group of NVIDIA GRID K1: 1 pGPU(s), vGPU types: passthrough, GRID K100
  - Group of NVIDIA GRID K1: 1 pGPU(s), vGPU types: passthrough, GRID K100
Allocation:      depth_first -> breadth_first
OK: gpu-inventory
```

</details>

## Go

Source: [`go/gpu_inventory.go`](../../go/gpu_inventory.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// gpuInventory - GPU inventory.
//
// Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.
//
// Run it:
//
//	gpuInventory("https://xenserver", "root", password)
func gpuInventory(url, user, password string) {
	session := connect(url, user, password)
	groups, err := xenapi.GPUGroup.GetAllRecords(session)
	check(err)
	fmt.Printf("GPU groups (%d):\n", len(groups))
	var firstGroup xenapi.GPUGroupRef
	haveGroup := false
	for ref, group := range groups {
		var types []string
		for _, t := range group.SupportedVGPUTypes {
			model, _ := xenapi.VGPUType.GetModelName(session, t)
			types = append(types, model)
		}
		fmt.Printf("  - %s: %d pGPU(s), vGPU types: %s\n",
			group.NameLabel, len(group.PGPUs), strings.Join(types, ", "))
		if !haveGroup {
			firstGroup, haveGroup = ref, true
		}
	}

	// How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU full
	// before using the next, breadth-first spreads them out.
	before, err := xenapi.GPUGroup.GetAllocationAlgorithm(session, firstGroup)
	check(err)
	check(xenapi.GPUGroup.SetAllocationAlgorithm(session, firstGroup, xenapi.AllocationAlgorithmBreadthFirst))
	after, _ := xenapi.GPUGroup.GetAllocationAlgorithm(session, firstGroup)
	fmt.Printf("Allocation:      %s -> %s\n", before, after)
	check(xenapi.GPUGroup.SetAllocationAlgorithm(session, firstGroup, before))

	fmt.Println("OK: gpu-inventory")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
GPU groups (2):
  - Group of NVIDIA GRID K1: 1 pGPU(s), vGPU types: passthrough, GRID K100
  - Group of NVIDIA GRID K1: 1 pGPU(s), vGPU types: passthrough, GRID K100
Allocation:      depth_first -> breadth_first
OK: gpu-inventory
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/GpuInventory.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/GpuInventory.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.GPUGroup;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VGPUType;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class GpuInventory {
    private GpuInventory() {
    }

    /**
     * GPU inventory.
     *
     * <p>Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * GpuInventory.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Map<GPUGroup, GPUGroup.Record> groups = GPUGroup.getAllRecords(conn);
        System.out.println("GPU groups (" + groups.size() + "):");
        for (GPUGroup.Record group : groups.values()) {
            StringBuilder types = new StringBuilder();
            for (VGPUType t : group.supportedVGPUTypes) {
                if (types.length() > 0) types.append(", ");
                types.append(t.getModelName(conn));
            }
            System.out.println("  - " + group.nameLabel + ": " + group.PGPUs.size()
                    + " pGPU(s), vGPU types: " + types);
        }
        // How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU
        // full before using the next, breadth-first spreads them out.
        GPUGroup groupRef = groups.keySet().iterator().next();
        Types.AllocationAlgorithm before = groupRef.getAllocationAlgorithm(conn);
        groupRef.setAllocationAlgorithm(conn, Types.AllocationAlgorithm.BREADTH_FIRST);
        System.out.println("Allocation:      " + before + " -> " + groupRef.getAllocationAlgorithm(conn));
        groupRef.setAllocationAlgorithm(conn, before);
        System.out.println("OK: gpu-inventory");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
GPU groups (2):
  - Group of NVIDIA GRID K1: 1 pGPU(s), vGPU types: passthrough, GRID K100
  - Group of NVIDIA GRID K1: 1 pGPU(s), vGPU types: GRID K100, passthrough
Allocation:      depth_first -> breadth_first
OK: gpu-inventory
```

</details>
