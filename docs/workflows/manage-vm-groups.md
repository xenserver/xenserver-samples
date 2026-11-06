<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage VM groups

Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then take the VM out again and delete the group.

Workflow `manage-vm-groups`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-ManageVmGroups.ps1`](../../powershell/VirtualMachines/Invoke-ManageVmGroups.ps1)

```powershell
function Invoke-ManageVmGroups {
    <#
    .SYNOPSIS
        Manage VM groups.
    .DESCRIPTION
        Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then
        take the VM out again and delete the group.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName,
        [string]$GroupName = "sdk-example-group"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }

    # anti_affinity asks the pool to keep the group's members on different hosts.
    $group = New-XenVMGroup -NameLabel $GroupName `
        -NameDescription 'Anti-affinity group created by the SDK example' `
        -Placement anti_affinity -PassThru
    Write-Host "Created group:  $($group.uuid)"

    # Membership is written from the VM side...
    Set-XenVM -VM $vm -Groups @($group)

    # ...and read back from the group side, which is the half that is easy to get wrong.
    $members = (Get-XenVMGroup -Ref $group).VMs
    Write-Host "Group members:  $($members.Count)"
    foreach ($m in $members) { Write-Host "  $((Get-XenVM -Ref $m).name_label)" }

    # VM_group.destroy already clears the group from every member VM's groups field - no need to remove
    # membership ourselves first.
    Remove-XenVMGroup -Ref $group
    Write-Host "OK: manage-vm-groups"
    Disconnect-XenServer -Session $session
}
```

<details><summary>Example output</summary>

```text
Created group:  00000001-0000-0000-180a-000000000000
Group members:  1
  web-01
OK: manage-vm-groups
```

</details>

## xe CLI

Source: [`cli/virtual-machines/manage-vm-groups.sh`](../../cli/virtual-machines/manage-vm-groups.sh)

```bash
# Manage VM groups.
#
# Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then take
# the VM out again and delete the group.
#
# Run it:
#   ./workflows.sh manage-vm-groups https://xenserver root "$password"

manage_vm_groups() {
    vm=$(vm_uuid web-01)
    # anti-affinity asks the pool to keep the group's members on different hosts.
    group=$(xe vm-group-create name-label=xe-example-group placement=anti-affinity)
    echo "Created group:  $group"

    # Membership is written from the VM side, and read back from the group side.
    xe vm-param-set uuid=$vm groups=$group
    echo "Group members:  $(count_csv "$(set_to_csv "$(xe vm-group-param-get uuid=$group param-name=vm-uuids)")")"

    # vm-group-destroy already clears the group from every member VM on its own - no need to remove
    # membership ourselves first.
    xe vm-group-destroy uuid=$group
    echo "OK: manage-vm-groups"
}
```

<details><summary>Example output</summary>

```text
Created group:  00000001-0000-0000-160a-000000000000
Group members:  0
OK: manage-vm-groups
```

</details>

## Python

Source: [`python/virtual_machines/manage_vm_groups.py`](../../python/virtual_machines/manage_vm_groups.py)

```python
"""Manage VM groups.

Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then
take the VM out again and delete the group.

Run it::

    manage_vm_groups("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def manage_vm_groups(url, username, password, vm_name, group_name="sdk-example-group"):
    """Create an anti-affinity VM group, add a VM, read the membership back, then tidy up."""
    session = connect(url, username, password)
    vm_ref = vm_by_name(session, vm_name)

    # anti_affinity asks the pool to keep the group's members on different hosts.
    group_ref = session.xenapi.VM_group.create({
        "name_label": group_name,
        "name_description": "Anti-affinity group created by the SDK example",
        "placement": "anti_affinity",
    })
    print("Created group:  %s" % session.xenapi.VM_group.get_uuid(group_ref))

    # Membership is written from the VM side...
    session.xenapi.VM.set_groups(vm_ref, [group_ref])

    # ...and read back from the group side, which is the half that is easy to get wrong.
    members = session.xenapi.VM_group.get_VMs(group_ref)
    print("Group members:  %d" % len(members))
    for m in members:
        print("  %s" % session.xenapi.VM.get_name_label(m))

    # VM_group.destroy already clears the group from every member VM's groups field - no need to
    # remove membership ourselves first.
    session.xenapi.VM_group.destroy(group_ref)
    print("OK: manage-vm-groups")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Created group:  00000001-0000-0000-150a-000000000000
Group members:  1
  web-01
OK: manage-vm-groups
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/ManageVmGroups.cs`](../../csharp/VirtualMachines/ManageVmGroups.cs)

```csharp
/// <summary>
/// Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then
/// take the VM out again and delete the group.
/// </summary>
/// <example>
/// <code>
/// Workflows.ManageVmGroups("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void ManageVmGroups(string url, string user, string password,
    string vmName, string groupName = "sdk-example-group")
{
    var session = Connect(url, user, password);
    var vmRef = VmByName(session, vmName);

    // anti_affinity asks the pool to keep the group's members on different hosts.
    var groupRef = VM_group.create(session, new VM_group
    {
        name_label = groupName,
        name_description = "Anti-affinity group created by the SDK example",
        placement = placement_policy.anti_affinity,
    });
    Console.WriteLine($"Created group:  {VM_group.get_uuid(session, groupRef)}");

    // Membership is written from the VM side...
    VM.set_groups(session, vmRef, new List<XenRef<VM_group>> { groupRef });

    // ...and read back from the group side, which is the half that is easy to get wrong.
    var members = VM_group.get_VMs(session, groupRef);
    Console.WriteLine($"Group members:  {members.Count}");
    foreach (var m in members)
        Console.WriteLine($"  {VM.get_name_label(session, m)}");

    // VM_group.destroy already clears the group from every member VM's groups field - no need to
    // remove membership ourselves first.
    VM_group.destroy(session, groupRef);
    Console.WriteLine("OK: manage-vm-groups");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Created group:  00000001-0000-0000-180a-000000000000
Group members:  1
  web-01
OK: manage-vm-groups
```

</details>

## Go

Source: [`go/manage_vm_groups.go`](../../go/manage_vm_groups.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// manageVMGroups - Manage VM groups.
//
// Create an anti-affinity VM group, put a VM in it, read the membership back from the group side,
// then take the VM out again and delete the group.
func manageVMGroups(url, user, password, vmName, groupName string) {
	session := connect(url, user, password)
	vmRef := vmByName(session, vmName)

	// anti_affinity asks the pool to keep the group's members on different hosts.
	groupRef, err := xenapi.VMGroup.Create(session, xenapi.VMGroupRecord{
		NameLabel:       groupName,
		NameDescription: "Anti-affinity group created by the SDK example",
		Placement:       xenapi.PlacementPolicyAntiAffinity,
	})
	check(err)
	groupUUID, _ := xenapi.VMGroup.GetUUID(session, groupRef)
	fmt.Printf("Created group:  %s\n", groupUUID)

	// Membership is written from the VM side...
	check(xenapi.VM.SetGroups(session, vmRef, []xenapi.VMGroupRef{groupRef}))

	// ...and read back from the group side, which is the half that is easy to get wrong.
	members, err := xenapi.VMGroup.GetVMs(session, groupRef)
	check(err)
	fmt.Printf("Group members:  %d\n", len(members))
	for _, m := range members {
		name, _ := xenapi.VM.GetNameLabel(session, m)
		fmt.Printf("  %s\n", name)
	}

	// VM_group.destroy already clears the group from every member VM's groups field - no need to
	// remove membership ourselves first.
	check(xenapi.VMGroup.Destroy(session, groupRef))
	fmt.Println("OK: manage-vm-groups")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Created group:  00000001-0000-0000-1a0a-000000000000
Group members:  1
  web-01
OK: manage-vm-groups
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/ManageVmGroups.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/ManageVmGroups.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VMGroup;

import java.util.LinkedHashSet;
import java.util.Set;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVmGroups {
    private ManageVmGroups() {
    }

    /**
     * Manage VM groups.
     *
     * <p>Create an anti-affinity VM group, put a VM in it, read the membership back from the group side,
     * then take the VM out again and delete the group.
     */
    public static void run(String url, String user, String password,
            String vmName, String groupName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);

        // anti_affinity asks the pool to keep the group's members on different hosts.
        VMGroup.Record spec = new VMGroup.Record();
        spec.nameLabel = groupName;
        spec.nameDescription = "Anti-affinity group created by the SDK example";
        spec.placement = Types.PlacementPolicy.ANTI_AFFINITY;
        VMGroup group = VMGroup.create(conn, spec);
        System.out.println("Created group:  " + group.getUuid(conn));

        // Membership is written from the VM side...
        Set<VMGroup> groups = new LinkedHashSet<>();
        groups.add(group);
        vm.setGroups(conn, groups);

        // ...and read back from the group side, which is the half that is easy to get wrong.
        Set<VM> members = group.getVMs(conn);
        System.out.println("Group members:  " + members.size());
        for (VM m : members) {
            System.out.println("  " + m.getNameLabel(conn));
        }

        // VM_group.destroy already clears the group from every member VM's groups field - no need to
        // remove membership ourselves first.
        group.destroy(conn);
        System.out.println("OK: manage-vm-groups");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Created group:  00000001-0000-0000-120a-000000000000
Group members:  1
  web-01
OK: manage-vm-groups
```

</details>
