<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Delete a VM

Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are destroyed explicitly afterward.

Workflow `delete-vm`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-DeleteVm.ps1`](../../powershell/VirtualMachines/Invoke-DeleteVm.ps1)

```powershell
function Invoke-DeleteVm {
    <#
    .SYNOPSIS
        Delete a VM.
    .DESCRIPTION
        Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are destroyed
        explicitly afterward.
    .EXAMPLE
        Invoke-DeleteVm -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-delete"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Make a throwaway VM to delete. Remove-XenVM removes the VM but leaves its disks, so the owned
    # VDIs are destroyed explicitly afterward.
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm.opaque_ref
    $uuid = (Get-XenVM -Ref $vm.opaque_ref).uuid

    $vdis = (Get-XenVM -Ref $vm.opaque_ref).VBDs |
        ForEach-Object { Get-XenVBD -Ref $_.opaque_ref } |
        Where-Object { $_.type -eq 'Disk' } |
        ForEach-Object { $_.VDI.opaque_ref }
    Write-Host "Deleting VM $uuid with $(@($vdis).Count) disk(s)"

    $vm | Remove-XenVM
    $vdis | ForEach-Object { Remove-XenVDI -Ref $_ }

    $stillThere = [bool](Get-XenVM | Where-Object { $_.uuid -eq $uuid })
    Write-Host "VM still present: $stillThere"
    Write-Host "OK: delete-vm"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Deleting VM 00000001-0000-0000-110a-000000000000 with 1 disk(s)
VM still present: False
OK: delete-vm
```

</details>

## xe CLI

Source: [`cli/virtual-machines/delete-vm.sh`](../../cli/virtual-machines/delete-vm.sh)

```bash
# Delete a VM.
#
# Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are destroyed
# explicitly afterward.
#
# Run it:
#   ./workflows.sh delete-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

delete_vm() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-example-delete)
    # vm-uninstall destroys the VM and the disks it owns; vm-destroy would remove only the VM record
    # and leave its disks behind.
    xe vm-uninstall uuid=$vm force=true
    echo "VM still present: $([ -z "$(xe vm-list uuid=$vm --minimal)" ] && echo false || echo true)"
    echo "OK: delete-vm"
}
```

<details><summary>Example output</summary>

```text
VM still present: false
OK: delete-vm
```

</details>

## Python

Source: [`python/virtual_machines/delete_vm.py`](../../python/virtual_machines/delete_vm.py)

```python
"""Delete a VM.

Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are destroyed
explicitly afterward.

Run it::

    delete_vm("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import disk_vdis, provision, template_by_name


def delete_vm(url, username, password, template_name, new_vm_name="sdk-example-delete"):
    """Make a throwaway VM, then delete it: VM.destroy removes the VM but leaves its disks, so the
    owned VDIs are destroyed explicitly afterward."""
    session = connect(url, username, password)
    vm = session.xenapi.VM.clone(template_by_name(session, template_name), new_vm_name)
    provision(session, vm)
    uuid = session.xenapi.VM.get_uuid(vm)
    vdis = disk_vdis(session, vm)
    print("Deleting VM %s with %d disk(s)" % (uuid, len(vdis)))

    session.xenapi.VM.destroy(vm)
    for vdi in vdis:
        session.xenapi.VDI.destroy(vdi)

    still_there = any(r["uuid"] == uuid for r in session.xenapi.VM.get_all_records().values())
    print("VM still present: %s" % still_there)
    print("OK: delete-vm")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Deleting VM 00000001-0000-0000-f809-000000000000 with 1 disk(s)
VM still present: False
OK: delete-vm
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/DeleteVm.cs`](../../csharp/VirtualMachines/DeleteVm.cs)

```csharp
/// <summary>
/// Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are destroyed
/// explicitly afterward.
/// </summary>
/// <example>
/// <code>
/// Workflows.DeleteVm("https://xenserver", "root", password, "Rocky Linux 8");
/// </code>
/// </example>
public static void DeleteVm(string url, string user, string password,
    string templateName, string newVmName = "sdk-example-delete")
{
    var session = Connect(url, user, password);
    // Make a throwaway VM to delete. VM.destroy removes the VM but leaves its disks, so the
    // owned VDIs are destroyed explicitly afterward.
    var vm = VM.clone(session, TemplateByName(session, templateName), newVmName).opaque_ref;
    Provision(session, vm);
    var uuid = VM.get_uuid(session, vm);
    var vdis = DiskVdis(session, vm);
    Console.WriteLine($"Deleting VM {uuid} with {vdis.Count} disk(s)");

    VM.destroy(session, vm);
    foreach (var vdi in vdis) VDI.destroy(session, vdi);

    var stillThere = VM.get_all_records(session).Values.Any(v => v.uuid == uuid);
    Console.WriteLine($"VM still present: {stillThere}");
    Console.WriteLine("OK: delete-vm");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Deleting VM 00000001-0000-0000-160a-000000000000 with 1 disk(s)
VM still present: False
OK: delete-vm
```

</details>

## Go

Source: [`go/delete_vm.go`](../../go/delete_vm.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// deleteVM - Delete a VM.
//
// Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are
// destroyed explicitly afterward.
//
// Run it:
//
//	deleteVM("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-delete")
func deleteVM(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	// Make a throwaway VM to delete. VM.Destroy removes the VM but leaves its disks, so the
	// owned VDIs are destroyed explicitly afterward.
	vm, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vm)
	uuid, _ := xenapi.VM.GetUUID(session, vm)
	vdis := diskVdis(session, vm)
	fmt.Printf("Deleting VM %s with %d disk(s)\n", uuid, len(vdis))

	check(xenapi.VM.Destroy(session, vm))
	for _, vdi := range vdis {
		check(xenapi.VDI.Destroy(session, vdi))
	}

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	stillThere := false
	for _, v := range vms {
		if v.UUID == uuid {
			stillThere = true
			break
		}
	}
	fmt.Printf("VM still present: %v\n", stillThere)
	fmt.Println("OK: delete-vm")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Deleting VM 00000001-0000-0000-1e0a-000000000000 with 1 disk(s)
VM still present: false
OK: delete-vm
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/DeleteVm.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/DeleteVm.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.Set;

import static com.xenserver.samples.Helpers.diskVdis;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class DeleteVm {
    private DeleteVm() {
    }

    /**
     * Delete a VM.
     *
     * <p>Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are
     * destroyed explicitly afterward.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * DeleteVm.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-delete");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        // Make a throwaway VM to delete. VM.destroy removes the VM but leaves its disks, so the
        // owned VDIs are destroyed explicitly afterward.
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm);
        String uuid = vm.getUuid(conn);
        Set<VDI> vdis = diskVdis(conn, vm);
        System.out.println("Deleting VM " + uuid + " with " + vdis.size() + " disk(s)");

        vm.destroy(conn);
        for (VDI vdi : vdis) vdi.destroy(conn);

        boolean stillThere = false;
        for (VM.Record r : VM.getAllRecords(conn).values())
            if (uuid.equals(r.uuid)) { stillThere = true; break; }
        System.out.println("VM still present: " + stillThere);
        System.out.println("OK: delete-vm");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Deleting VM 00000001-0000-0000-120a-000000000000 with 1 disk(s)
VM still present: false
OK: delete-vm
```

</details>
