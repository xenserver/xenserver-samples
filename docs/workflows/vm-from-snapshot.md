<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create a VM and a template from a snapshot

Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.

Workflow `vm-from-snapshot`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-VmFromSnapshot.ps1`](../../powershell/VirtualMachines/Invoke-VmFromSnapshot.ps1)

```powershell
function Invoke-VmFromSnapshot {
    <#
    .SYNOPSIS
        Create a VM and a template from a snapshot.
    .DESCRIPTION
        Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.
    .EXAMPLE
        Invoke-VmFromSnapshot -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = 'db-01'
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # A snapshot is a VM record with is_a_snapshot (and is_a_template) set, and cloning it gives a custom
    # template that stands on its own while the snapshot stays put.
    $vm = Get-XenVM -Name $VmName | Select-Object -First 1
    $snapshot = $vm | Invoke-XenVM -XenAction Snapshot -NewName 'sdk-example-source-snapshot' -PassThru
    Write-Host "Snapshot of $VmName taken"

    # A clone of a snapshot is a template, not another snapshot: it stands on its own instead of being
    # filed under the original VM. Provision it to get an ordinary VM you can start.
    $newVm = $snapshot | Invoke-XenVM -XenAction Clone -NewName 'sdk-example-vm-from-snapshot' -PassThru
    Invoke-VmProvision -Ref $newVm.opaque_ref
    Write-Host "  new VM:      $($newVm.name_label) (is_a_template=$((Get-XenVM -Ref $newVm.opaque_ref).is_a_template))"

    # Another clone, left as the template it already is: a starting point to stamp more VMs from.
    $template = $snapshot | Invoke-XenVM -XenAction Clone -NewName 'sdk-example-template-from-snapshot' -PassThru
    Write-Host "  new template:$($template.name_label) (is_a_template=$((Get-XenVM -Ref $template.opaque_ref).is_a_template))"

    # Each clone made its own disks, and the snapshot has its own snapshot disks; destroy them all.
    foreach ($ref in @($newVm.opaque_ref, $template.opaque_ref, $snapshot.opaque_ref)) {
        Remove-VmAndDisks -Ref $ref
    }
    Write-Host "OK: vm-from-snapshot"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Snapshot of db-01 taken
  new VM:      sdk-example-vm-from-snapshot (is_a_template=False)
  new template:sdk-example-template-from-snapshot (is_a_template=True)
OK: vm-from-snapshot
```

</details>

## xe CLI

Source: [`cli/virtual-machines/vm-from-snapshot.sh`](../../cli/virtual-machines/vm-from-snapshot.sh)

```bash
# Create a VM and a template from a snapshot.
#
# Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.
#
# Run it:
#   ./workflows.sh vm-from-snapshot https://xenserver root "$password"

vm_from_snapshot() {
    # A snapshot is a VM record with is-a-snapshot (and is-a-template) set, so xe can install a VM from it
    # like from any template, or clone it into a custom template that stands on its own.
    vm=$(vm_uuid db-01)
    snap=$(xe vm-snapshot uuid=$vm new-name-label=xe-example-source-snapshot)
    echo "Snapshot of db-01 taken"

    # vm-install from the snapshot gives an ordinary VM you can start, as from any template.
    newvm=$(xe vm-install template-uuid=$snap new-name-label=xe-example-vm-from-snapshot)
    echo "  new VM:      $(xe vm-param-get uuid=$newvm param-name=name-label) (is-a-template=$(xe vm-param-get uuid=$newvm param-name=is-a-template))"

    # snapshot-clone gives a template, not another snapshot: a starting point to stamp more VMs from.
    tmpl=$(xe snapshot-clone uuid=$snap new-name-label=xe-example-template-from-snapshot)
    echo "  new template:$(xe template-param-get uuid=$tmpl param-name=name-label) (is-a-template=$(xe template-param-get uuid=$tmpl param-name=is-a-template))"

    # Each made its own disks, and the snapshot has its own snapshot disks; the -uninstall commands destroy
    # them along with the records.
    xe vm-uninstall uuid=$newvm force=true
    xe template-uninstall template-uuid=$tmpl force=true
    xe snapshot-uninstall snapshot-uuid=$snap force=true
    echo "OK: vm-from-snapshot"
}
```

<details><summary>Example output</summary>

```text
Snapshot of db-01 taken
  new VM:      xe-example-vm-from-snapshot (is-a-template=false)
  new template:xe-example-template-from-snapshot (is-a-template=true)
OK: vm-from-snapshot
```

</details>

## Python

Source: [`python/virtual_machines/vm_from_snapshot.py`](../../python/virtual_machines/vm_from_snapshot.py)

```python
"""Create a VM and a template from a snapshot.

Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.

Run it::

    vm_from_snapshot("https://xenserver", "root", password, "db-01")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, vm_by_name


def vm_from_snapshot(url, username, password, vm_name="db-01"):
    """Turn a snapshot into a new VM, and into a reusable custom template.

    A snapshot is a VM record with is_a_snapshot (and is_a_template) set, and cloning it gives a
    custom template that stands on its own while the snapshot stays put. That clone already is the
    template; provisioning another clone turns it into a VM, exactly as with any template."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = vm_by_name(session, vm_name)
    snapshot = x.VM.snapshot(vm, "sdk-example-source-snapshot")
    print("Snapshot of %s taken" % vm_name)

    # A clone of a snapshot is a template, not another snapshot: it stands on its own instead of
    # being filed under the original VM. Provision it to get an ordinary VM you can start.
    new_vm = x.VM.clone(snapshot, "sdk-example-vm-from-snapshot")
    provision(session, new_vm)
    print("  new VM:      %s (is_a_template=%s)"
          % (x.VM.get_name_label(new_vm), x.VM.get_is_a_template(new_vm)))

    # Another clone, left as the template it already is: a starting point to stamp more VMs from.
    template = x.VM.clone(snapshot, "sdk-example-template-from-snapshot")
    print("  new template:%s (is_a_template=%s)"
          % (x.VM.get_name_label(template), x.VM.get_is_a_template(template)))

    # Each clone made its own disks, and the snapshot has its own snapshot disks; destroy them all.
    for ref in (new_vm, template):
        destroy_vm_and_disks(session, ref)
    destroy_vm_and_disks(session, snapshot)
    print("OK: vm-from-snapshot")
    session.logout()
```

<details><summary>Example output</summary>

```text
Snapshot of db-01 taken
  new VM:      sdk-example-vm-from-snapshot (is_a_template=False)
  new template:sdk-example-template-from-snapshot (is_a_template=True)
OK: vm-from-snapshot
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/VmFromSnapshot.cs`](../../csharp/VirtualMachines/VmFromSnapshot.cs)

```csharp
/// <summary>
/// Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.
/// </summary>
/// <example>
/// <code>
/// Workflows.VmFromSnapshot("https://xenserver", "root", password, "db-01");
/// </code>
/// </example>
public static void VmFromSnapshot(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);

    // A snapshot is a VM record with is_a_snapshot (and is_a_template) set, and cloning it gives a
    // custom template that stands on its own while the snapshot stays put.
    var vm = VmByName(session, vmName);
    var snapshot = VM.snapshot(session, vm, "sdk-example-source-snapshot").opaque_ref;
    Console.WriteLine($"Snapshot of {vmName} taken");

    // A clone of a snapshot is a template, not another snapshot: it stands on its own instead of
    // being filed under the original VM. Provision it to get an ordinary VM you can start.
    var newVm = VM.clone(session, snapshot, "sdk-example-vm-from-snapshot").opaque_ref;
    Provision(session, newVm);
    Console.WriteLine($"  new VM:      {VM.get_name_label(session, newVm)} "
                      + $"(is_a_template={VM.get_is_a_template(session, newVm)})");

    // Another clone, left as the template it already is: a starting point to stamp more VMs from.
    var template = VM.clone(session, snapshot, "sdk-example-template-from-snapshot").opaque_ref;
    Console.WriteLine($"  new template:{VM.get_name_label(session, template)} "
                      + $"(is_a_template={VM.get_is_a_template(session, template)})");

    foreach (var r in new[] { newVm, template, snapshot }) DestroyVmAndDisks(session, r);
    Console.WriteLine("OK: vm-from-snapshot");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Snapshot of db-01 taken
  new VM:      sdk-example-vm-from-snapshot (is_a_template=False)
  new template:sdk-example-template-from-snapshot (is_a_template=True)
OK: vm-from-snapshot
```

</details>

## Go

Source: [`go/vm_from_snapshot.go`](../../go/vm_from_snapshot.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// vmFromSnapshot - Create a VM and a template from a snapshot.
//
// Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.
//
// Run it:
//
//	vmFromSnapshot("https://xenserver", "root", password, "db-01")
func vmFromSnapshot(url, user, password, vmName string) {
	session := connect(url, user, password)
	defer session.Logout()

	// A snapshot is a VM record with is_a_snapshot (and is_a_template) set, and cloning it gives a custom
	// template that stands on its own while the snapshot stays put.
	vm := vmByName(session, vmName)
	snapshot, err := xenapi.VM.Snapshot(session, vm, "sdk-example-source-snapshot", nil)
	check(err)
	fmt.Printf("Snapshot of %s taken\n", vmName)

	// A clone of a snapshot is a template, not another snapshot: it stands on its own instead of being
	// filed under the original VM. Provision it to get an ordinary VM you can start.
	newVM, err := xenapi.VM.Clone(session, snapshot, "sdk-example-vm-from-snapshot")
	check(err)
	provision(session, newVM)
	newName, _ := xenapi.VM.GetNameLabel(session, newVM)
	newIsTmpl, _ := xenapi.VM.GetIsATemplate(session, newVM)
	fmt.Printf("  new VM:      %s (is_a_template=%t)\n", newName, newIsTmpl)

	// Another clone, left as the template it already is: a starting point to stamp more VMs from.
	template, err := xenapi.VM.Clone(session, snapshot, "sdk-example-template-from-snapshot")
	check(err)
	tmplName, _ := xenapi.VM.GetNameLabel(session, template)
	isTmpl, _ := xenapi.VM.GetIsATemplate(session, template)
	fmt.Printf("  new template:%s (is_a_template=%t)\n", tmplName, isTmpl)

	// Each clone made its own disks, and the snapshot has its own snapshot disks; destroy them all.
	for _, ref := range []xenapi.VMRef{newVM, template, snapshot} {
		destroyVMAndDisks(session, ref)
	}
	fmt.Println("OK: vm-from-snapshot")
}
```

<details><summary>Example output</summary>

```text
Snapshot of db-01 taken
  new VM:      sdk-example-vm-from-snapshot (is_a_template=false)
  new template:sdk-example-template-from-snapshot (is_a_template=true)
OK: vm-from-snapshot
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/VmFromSnapshot.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/VmFromSnapshot.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class VmFromSnapshot {
    private VmFromSnapshot() {
    }

    /**
     * Create a VM and a template from a snapshot.
     *
     * <p>Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * VmFromSnapshot.run("https://xenserver", "root", password, "db-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // A snapshot is a VM record with is_a_snapshot (and is_a_template) set, and cloning it gives a
            // custom template that stands on its own while the snapshot stays put.
            VM vm = vmByName(conn, vmName);
            VM snapshot = vm.snapshot(conn, "sdk-example-source-snapshot");
            System.out.println("Snapshot of " + vmName + " taken");

            // A clone of a snapshot is a template, not another snapshot: it stands on its own instead of
            // being filed under the original VM. Provision it to get an ordinary VM you can start.
            VM newVm = snapshot.createClone(conn, "sdk-example-vm-from-snapshot");
            provision(conn, newVm);
            System.out.printf("  new VM:      %s (is_a_template=%s)%n",
                newVm.getNameLabel(conn), newVm.getIsATemplate(conn));

            // Another clone, left as the template it already is: a starting point to stamp more VMs from.
            VM template = snapshot.createClone(conn, "sdk-example-template-from-snapshot");
            System.out.printf("  new template:%s (is_a_template=%s)%n",
                template.getNameLabel(conn), template.getIsATemplate(conn));

            // Each clone owns its own disks, and so does the snapshot itself.
            destroyVmAndDisks(conn, newVm);
            destroyVmAndDisks(conn, template);
            destroyVmAndDisks(conn, snapshot);
            System.out.println("OK: vm-from-snapshot");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
Snapshot of db-01 taken
  new VM:      sdk-example-vm-from-snapshot (is_a_template=false)
  new template:sdk-example-template-from-snapshot (is_a_template=true)
OK: vm-from-snapshot
```

</details>
