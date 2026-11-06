<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create a VM with a vGPU

Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU type, attach it, and read the assignment back.

**Requires:** a GPU that supports vGPU, and a license that includes GPU virtualization (Premium Edition).

Workflow `create-vm-with-vgpu`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-CreateVmWithVgpu.ps1`](../../powershell/VirtualMachines/Invoke-CreateVmWithVgpu.ps1)

```powershell
function Invoke-CreateVmWithVgpu {
    <#
    .SYNOPSIS
        Create a VM with a vGPU.
    .DESCRIPTION
        Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU
        type, attach it, and read the assignment back.
    .EXAMPLE
        Invoke-CreateVmWithVgpu -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-vgpu-vm"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Find a GPU group that offers a real (non-passthrough) vGPU type, plus that type.
    $group = $null; $vgpuType = $null
    foreach ($g in Get-XenGPUGroup) {
        if (-not $g.PGPUs) { continue }
        foreach ($tRef in $g.supported_VGPU_types) {
            $t = Get-XenVGPUType -Ref $tRef
            if ($t.model_name -ne 'passthrough') { $group = $g; $vgpuType = $t; break }
        }
        if ($vgpuType) { break }
    }
    if (-not $vgpuType) { throw "No GPU group offers a vGPU type." }
    Write-Host "Using vGPU type: $($vgpuType.model_name) ($([int]($vgpuType.framebuffer_size / 1MB)) MB framebuffer)"

    # Provision a fresh VM from the template to attach the vGPU to.
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm.opaque_ref

    # Assign the vGPU: device "0" is the VM's first vGPU slot, other_config is empty.
    $vgpu = New-XenVGPU -VM $vm.opaque_ref -GPUGroup $group.opaque_ref -Device "0" -OtherConfig @{} -Type $vgpuType.opaque_ref -PassThru
    Write-Host "Created vGPU: $($vgpu.uuid)"

    # Read the assignment back.
    $assignedVm = Get-XenVM -Ref $vm.opaque_ref
    $assigned = (Get-XenVGPUType -Ref (Get-XenVGPU -Ref $assignedVm.VGPUs[0]).type).model_name
    Write-Host "VM now has $($assignedVm.VGPUs.Count) vGPU(s); type = $assigned"

    # Tidy up so the example is repeatable.
    $vgpu | Remove-XenVGPU
    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "Cleaned up the example VM and its vGPU."

    Write-Host "OK: create-vm-with-vgpu"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Using vGPU type: GRID K100 (256 MB framebuffer)
Created vGPU: 00000001-0000-0000-8c0a-000000000000
VM now has 1 vGPU(s); type = GRID K100
Cleaned up the example VM and its vGPU.
OK: create-vm-with-vgpu
```

</details>

## xe CLI

Source: [`cli/virtual-machines/create-vm-with-vgpu.sh`](../../cli/virtual-machines/create-vm-with-vgpu.sh)

```bash
# Create a VM with a vGPU.
#
# Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU type, attach
# it, and read the assignment back.
#
# Run it:
#   ./workflows.sh create-vm-with-vgpu https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

create_vm_with_vgpu() {
    # A GPU group that offers a real (non-passthrough) vGPU type, and that type. Not simply the first
    # group: a host's onboard display adapter is a GPU group too, with no vGPU types at all.
    group="" type=""
    for g in $(each_csv "$(xe gpu-group-list --minimal)"); do
        vtypes=$(set_to_csv "$(xe gpu-group-param-get uuid=$g param-name=supported-VGPU-types)")
        for t in ${vtypes//,/ }; do
            if [ "$(xe vgpu-type-param-get uuid=$t param-name=model-name)" != "passthrough" ]; then
                group=$g; type=$t; break 2
            fi
        done
    done
    [ -n "$type" ] || { echo "no GPU group offers a vGPU type (is the GPU vendor's host driver installed?)" >&2; return 1; }
    local template=$(param template_name "Rocky Linux 8")
    # No sr-uuid: the template's disks go to the pool's default SR, as VM.provision does.
    vm=$(xe vm-install template="$template" new-name-label=xe-example-vgpu)
    vgpu=$(xe vgpu-create vm-uuid=$vm gpu-group-uuid=$group vgpu-type-uuid=$type)
    echo "Created vGPU: $vgpu of type $(xe vgpu-type-param-get uuid=$type param-name=model-name)"
    # Tidy up so the example is repeatable: the vGPU, then the VM and the disks it owns.
    xe vgpu-destroy uuid=$vgpu
    xe vm-uninstall uuid=$vm force=true
    echo "OK: create-vm-with-vgpu"
}
```

<details><summary>Example output</summary>

```text
Created vGPU: 00000001-0000-0000-890a-000000000000 of type GRID K100
OK: create-vm-with-vgpu
```

</details>

## Python

Source: [`python/virtual_machines/create_vm_with_vgpu.py`](../../python/virtual_machines/create_vm_with_vgpu.py)

```python
"""Create a VM with a vGPU.

Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU
type, attach it, and read the assignment back.

Run it::

    create_vm_with_vgpu("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, template_by_name


def create_vm_with_vgpu(url, username, password, template_name, new_vm_name="sdk-example-vgpu-vm"):
    """Provision a VM from a template and assign it a virtual GPU (VGPU.create)."""
    session = connect(url, username, password)
    # Find a GPU group that offers a real (non-passthrough) vGPU type, plus that type.
    group_ref, vgpu_type_ref = gpu_group_with_vgpu_type(session)
    type_rec = session.xenapi.VGPU_type.get_record(vgpu_type_ref)
    print("Using vGPU type: %s (%d MB framebuffer)"
          % (type_rec["model_name"], int(type_rec["framebuffer_size"]) // (1024 * 1024)))

    # Provision a fresh VM from the template to attach the vGPU to.
    template_ref = template_by_name(session, template_name)
    vm_ref = session.xenapi.VM.clone(template_ref, new_vm_name)
    provision(session, vm_ref)

    # Assign the vGPU: device "0" is the VM's first vGPU slot, other_config is empty.
    vgpu_ref = session.xenapi.VGPU.create(vm_ref, group_ref, "0", {}, vgpu_type_ref)
    print("Created vGPU: %s" % session.xenapi.VGPU.get_uuid(vgpu_ref))

    # Read the assignment back.
    vgpus = session.xenapi.VM.get_VGPUs(vm_ref)
    assigned = session.xenapi.VGPU_type.get_model_name(session.xenapi.VGPU.get_type(vgpus[0]))
    print("VM now has %d vGPU(s); type = %s" % (len(vgpus), assigned))

    # Tidy up so the example is repeatable.
    session.xenapi.VGPU.destroy(vgpu_ref)
    destroy_vm_and_disks(session, vm_ref)
    print("Cleaned up the example VM and its vGPU.")
    print("OK: create-vm-with-vgpu")
    session.xenapi.session.logout()


def gpu_group_with_vgpu_type(session):
    """Find a (GPU_group, VGPU_type) pair where the group offers a non-passthrough vGPU type."""
    for group, r in session.xenapi.GPU_group.get_all_records().items():
        if not r["PGPUs"]:
            continue
        for type_ref in r["supported_VGPU_types"]:
            if session.xenapi.VGPU_type.get_model_name(type_ref) != "passthrough":
                return group, type_ref
    raise RuntimeError("no GPU group offers a vGPU type")
```

<details><summary>Example output</summary>

```text
Using vGPU type: GRID K100 (256 MB framebuffer)
Created vGPU: 00000001-0000-0000-780a-000000000000
VM now has 1 vGPU(s); type = GRID K100
Cleaned up the example VM and its vGPU.
OK: create-vm-with-vgpu
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/CreateVmWithVgpu.cs`](../../csharp/VirtualMachines/CreateVmWithVgpu.cs)

```csharp
/// <summary>
/// Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU type,
/// attach it, and read the assignment back.
/// </summary>
/// <example>
/// <code>
/// Workflows.CreateVmWithVgpu("https://xenserver", "root", password, "Rocky Linux 8");
/// </code>
/// </example>
public static void CreateVmWithVgpu(string url, string user, string password,
    string templateName, string newVmName = "sdk-example-vgpu-vm")
{
    var session = Connect(url, user, password);
    // Find a GPU group that offers a real (non-passthrough) vGPU type, plus that type.
    var (groupRef, typeRef) = GpuGroupWithVgpuType(session);
    var typeRec = VGPU_type.get_record(session, typeRef);
    Console.WriteLine($"Using vGPU type: {typeRec.model_name} ({typeRec.framebuffer_size / (1024 * 1024)} MB framebuffer)");

    // Provision a fresh VM from the template to attach the vGPU to.
    var templateRef = TemplateByName(session, templateName);
    var vmRef = VM.clone(session, templateRef, newVmName).opaque_ref;
    Provision(session, vmRef);

    // Assign the vGPU: device "0" is the VM's first vGPU slot, other_config is empty.
    var vgpuRef = VGPU.create(session, vmRef, groupRef, "0", new Dictionary<string, string>(), typeRef).opaque_ref;
    Console.WriteLine($"Created vGPU: {VGPU.get_uuid(session, vgpuRef)}");

    // Read the assignment back.
    var vgpus = VM.get_VGPUs(session, vmRef);
    var assigned = VGPU_type.get_model_name(session, VGPU.get_type(session, vgpus[0].opaque_ref).opaque_ref);
    Console.WriteLine($"VM now has {vgpus.Count} vGPU(s); type = {assigned}");

    // Tidy up so the example is repeatable.
    VGPU.destroy(session, vgpuRef);
    DestroyVmAndDisks(session, vmRef);
    Console.WriteLine("Cleaned up the example VM and its vGPU.");
    Console.WriteLine("OK: create-vm-with-vgpu");
    session.logout();
}

/// <summary>Find a (GPU_group, VGPU_type) pair where the group offers a non-passthrough vGPU
/// type.</summary>
private static (string, string) GpuGroupWithVgpuType(Session session)
{
    foreach (var (groupRef, group) in GPU_group.get_all_records(session))
    {
        if (group.PGPUs.Count == 0) continue;
        foreach (var typeRef in group.supported_VGPU_types)
            if (VGPU_type.get_model_name(session, typeRef.opaque_ref) != "passthrough")
                return (groupRef.opaque_ref, typeRef.opaque_ref);
    }
    throw new Exception("no GPU group offers a vGPU type");
}
```

<details><summary>Example output</summary>

```text
Using vGPU type: GRID K100 (256 MB framebuffer)
Created vGPU: 00000001-0000-0000-540a-000000000000
VM now has 1 vGPU(s); type = GRID K100
Cleaned up the example VM and its vGPU.
OK: create-vm-with-vgpu
```

</details>

## Go

Source: [`go/create_vm_with_vgpu.go`](../../go/create_vm_with_vgpu.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// createVMWithVgpu - Create a VM with a vGPU.
//
// Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU
// type, attach it, and read the assignment back.
//
// Run it:
//
//	createVMWithVgpu("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vgpu-vm")
func createVMWithVgpu(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	// Find a GPU group that offers a real (non-passthrough) vGPU type, plus that type.
	groupRef, typeRef := gpuGroupWithVgpuType(session)
	typeRec, err := xenapi.VGPUType.GetRecord(session, typeRef)
	check(err)
	fmt.Printf("Using vGPU type: %s (%d MB framebuffer)\n", typeRec.ModelName, typeRec.FramebufferSize/(1024*1024))

	// Provision a fresh VM from the template to attach the vGPU to.
	vmRef, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vmRef)

	// Assign the vGPU: device "0" is the VM's first vGPU slot, other_config is empty.
	vgpuRef, err := xenapi.VGPU.Create(session, vmRef, groupRef, "0", map[string]string{}, typeRef)
	check(err)
	uuid, _ := xenapi.VGPU.GetUUID(session, vgpuRef)
	fmt.Printf("Created vGPU: %s\n", uuid)

	// Read the assignment back.
	vgpus, _ := xenapi.VM.GetVGPUs(session, vmRef)
	assignedType, _ := xenapi.VGPU.GetType(session, vgpus[0])
	assigned, _ := xenapi.VGPUType.GetModelName(session, assignedType)
	fmt.Printf("VM now has %d vGPU(s); type = %s\n", len(vgpus), assigned)

	// Tidy up so the example is repeatable.
	check(xenapi.VGPU.Destroy(session, vgpuRef))
	destroyVMAndDisks(session, vmRef)
	fmt.Println("Cleaned up the example VM and its vGPU.")

	fmt.Println("OK: create-vm-with-vgpu")
	session.Logout()
}

// gpuGroupWithVgpuType finds a (GPU_group, VGPU_type) pair where the group offers a non-passthrough type.
func gpuGroupWithVgpuType(session *xenapi.Session) (xenapi.GPUGroupRef, xenapi.VGPUTypeRef) {
	groups, err := xenapi.GPUGroup.GetAllRecords(session)
	check(err)
	for ref, r := range groups {
		if len(r.PGPUs) == 0 {
			continue
		}
		for _, typeRef := range r.SupportedVGPUTypes {
			model, _ := xenapi.VGPUType.GetModelName(session, typeRef)
			if model != "passthrough" {
				return ref, typeRef
			}
		}
	}
	panic("no GPU group offers a vGPU type")
}
```

<details><summary>Example output</summary>

```text
Using vGPU type: GRID K100 (256 MB framebuffer)
Created vGPU: 00000001-0000-0000-800a-000000000000
VM now has 1 vGPU(s); type = GRID K100
Cleaned up the example VM and its vGPU.
OK: create-vm-with-vgpu
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/CreateVmWithVgpu.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/CreateVmWithVgpu.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.GPUGroup;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VGPU;
import com.xensource.xenapi.VGPUType;
import com.xensource.xenapi.VM;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateVmWithVgpu {
    private CreateVmWithVgpu() {
    }

    /**
     * Create a VM with a vGPU.
     *
     * <p>Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU
     * type, attach it, and read the assignment back.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateVmWithVgpu.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vgpu-vm");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        // Find a GPU group that offers a real (non-passthrough) vGPU type, plus that type.
        GPUGroup group = null;
        VGPUType vgpuType = null;
        outer:
        for (Map.Entry<GPUGroup, GPUGroup.Record> e : GPUGroup.getAllRecords(conn).entrySet()) {
            if (e.getValue().PGPUs.isEmpty()) continue;
            for (VGPUType t : e.getValue().supportedVGPUTypes) {
                if (!"passthrough".equals(t.getModelName(conn))) {
                    group = e.getKey();
                    vgpuType = t;
                    break outer;
                }
            }
        }
        if (group == null) throw new RuntimeException("no GPU group offers a vGPU type");
        System.out.println("Using vGPU type: " + vgpuType.getModelName(conn)
                + " (" + vgpuType.getFramebufferSize(conn) / (1024 * 1024) + " MB framebuffer)");

        // Provision a fresh VM from the template to attach the vGPU to.
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm);

        // Assign the vGPU: device "0" is the VM's first vGPU slot, other_config is empty.
        VGPU vgpu = VGPU.create(conn, vm, group, "0", new HashMap<String, String>(), vgpuType);
        System.out.println("Created vGPU: " + vgpu.getUuid(conn));

        // Read the assignment back.
        Set<VGPU> vgpus = vm.getVGPUs(conn);
        String assigned = vgpus.iterator().next().getType(conn).getModelName(conn);
        System.out.println("VM now has " + vgpus.size() + " vGPU(s); type = " + assigned);

        // Tidy up so the example is repeatable.
        vgpu.destroy(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("Cleaned up the example VM and its vGPU.");

        System.out.println("OK: create-vm-with-vgpu");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Using vGPU type: GRID K100 (256 MB framebuffer)
Created vGPU: 00000001-0000-0000-520a-000000000000
VM now has 1 vGPU(s); type = GRID K100
Cleaned up the example VM and its vGPU.
OK: create-vm-with-vgpu
```

</details>
