<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Edit VM properties

Change a VM's description and custom metadata, then read the changes back.

Workflow `edit-vm-properties`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/VirtualMachines/EditVmProperties.cs`](../../csharp/VirtualMachines/EditVmProperties.cs)

```csharp
/// <summary>
/// Change a VM's description and custom metadata, then read the changes back.
/// </summary>
/// <example>
/// <code>
/// Workflows.EditVmProperties("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void EditVmProperties(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);
    var vmRef = VmByName(session, vmName);

    var originalDesc = VM.get_name_description(session, vmRef);
    VM.set_name_description(session, vmRef, "Edited by the SDK example");
    VM.add_to_other_config(session, vmRef, "sdk_example", "true");
    Console.WriteLine($"New description: {VM.get_name_description(session, vmRef)}");
    Console.WriteLine($"other_config[sdk_example] = {VM.get_other_config(session, vmRef)["sdk_example"]}");

    VM.set_name_description(session, vmRef, originalDesc);
    VM.remove_from_other_config(session, vmRef, "sdk_example");
    Console.WriteLine("OK: edit-vm-properties");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
New description: Edited by the SDK example
other_config[sdk_example] = true
OK: edit-vm-properties
```

</details>

## Python

Source: [`python/virtual_machines/edit_vm_properties.py`](../../python/virtual_machines/edit_vm_properties.py)

```python
"""Edit VM properties.

Change a VM's description and custom metadata, then read the changes back.

Run it::

    edit_vm_properties("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def edit_vm_properties(url, username, password, vm_name):
    """Edit the named VM's description and other_config, then restore the originals."""
    session = connect(url, username, password)
    vm_ref = vm_by_name(session, vm_name)

    original_desc = session.xenapi.VM.get_name_description(vm_ref)
    session.xenapi.VM.set_name_description(vm_ref, "Edited by the SDK example")
    session.xenapi.VM.add_to_other_config(vm_ref, "sdk_example", "true")
    print("New description: %s" % session.xenapi.VM.get_name_description(vm_ref))
    print("other_config[sdk_example] = %s" %
          session.xenapi.VM.get_other_config(vm_ref).get("sdk_example"))

    # Restore original state.
    session.xenapi.VM.set_name_description(vm_ref, original_desc)
    session.xenapi.VM.remove_from_other_config(vm_ref, "sdk_example")
    print("OK: edit-vm-properties")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
New description: Edited by the SDK example
other_config[sdk_example] = true
OK: edit-vm-properties
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/EditVmProperties.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/EditVmProperties.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class EditVmProperties {
    private EditVmProperties() {
    }

    /**
     * Edit VM properties.
     *
     * <p>Change a VM's description and custom metadata, then read the changes back.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * EditVmProperties.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);

        String originalDesc = vm.getNameDescription(conn);
        vm.setNameDescription(conn, "Edited by the SDK example");
        vm.addToOtherConfig(conn, "sdk_example", "true");
        System.out.println("New description: " + vm.getNameDescription(conn));
        System.out.println("other_config[sdk_example] = " + vm.getOtherConfig(conn).get("sdk_example"));

        vm.setNameDescription(conn, originalDesc);
        vm.removeFromOtherConfig(conn, "sdk_example");
        System.out.println("OK: edit-vm-properties");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
New description: Edited by the SDK example
other_config[sdk_example] = true
OK: edit-vm-properties
```

</details>

## Go

Source: [`go/edit_vm_properties.go`](../../go/edit_vm_properties.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// editVMProperties - Edit VM properties.
//
// Change a VM's description and custom metadata, then read the changes back.
//
// Run it:
//
//	editVMProperties("https://xenserver", "root", password, "web-01")
func editVMProperties(url, user, password, vmName string) {
	session := connect(url, user, password)
	vmRef := vmByName(session, vmName)

	originalDesc, _ := xenapi.VM.GetNameDescription(session, vmRef)
	check(xenapi.VM.SetNameDescription(session, vmRef, "Edited by the SDK example"))
	check(xenapi.VM.AddToOtherConfig(session, vmRef, "sdk_example", "true"))
	desc, _ := xenapi.VM.GetNameDescription(session, vmRef)
	fmt.Printf("New description: %s\n", desc)
	oc, _ := xenapi.VM.GetOtherConfig(session, vmRef)
	fmt.Printf("other_config[sdk_example] = %s\n", oc["sdk_example"])

	check(xenapi.VM.SetNameDescription(session, vmRef, originalDesc))
	check(xenapi.VM.RemoveFromOtherConfig(session, vmRef, "sdk_example"))
	fmt.Println("OK: edit-vm-properties")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
New description: Edited by the SDK example
other_config[sdk_example] = true
OK: edit-vm-properties
```

</details>

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-EditVmProperties.ps1`](../../powershell/VirtualMachines/Invoke-EditVmProperties.ps1)

```powershell
function Invoke-EditVmProperties {
    <#
    .SYNOPSIS
        Edit VM properties.
    .DESCRIPTION
        Change a VM's description and custom metadata, then read the changes back.
    .EXAMPLE
        Invoke-EditVmProperties -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $originalDesc = $vm.name_description

    # Set-XenVM -OtherConfig replaces the whole map, so copy the current one, add our entry and write it
    # back (leaving the VM's existing keys intact).
    $current = $vm.other_config
    $oc = @{}
    foreach ($k in $current.Keys) { $oc[$k] = $current[$k] }
    $oc["sdk_example"] = "true"
    $vm | Set-XenVM -NameDescription "Edited by the SDK example"
    $vm | Set-XenVM -OtherConfig $oc

    $edited = Get-XenVM -Ref $vm.opaque_ref
    Write-Host "New description: $($edited.name_description)"
    Write-Host "other_config[sdk_example] = $($edited.other_config['sdk_example'])"

    # Put it back so the example is repeatable: restore the description and drop the key we added.
    $vm | Set-XenVM -NameDescription $originalDesc
    $vm | Remove-XenVMProperty -OtherConfig "sdk_example"
    Write-Host "OK: edit-vm-properties"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
New description: Edited by the SDK example
other_config[sdk_example] = true
OK: edit-vm-properties
```

</details>

## xe CLI

Source: [`cli/virtual-machines/edit-vm-properties.sh`](../../cli/virtual-machines/edit-vm-properties.sh)

```bash
# Edit VM properties.
#
# Change a VM's description and custom metadata, then read the changes back.
#
# Run it:
#   ./workflows.sh edit-vm-properties https://xenserver root "$password"

edit_vm_properties() {
    vm=$(vm_uuid web-01)
    original=$(xe vm-param-get uuid=$vm param-name=name-description)
    xe vm-param-set uuid=$vm name-description="Edited by the xe example"
    xe vm-param-add uuid=$vm param-name=other-config xe_example=true
    echo "New description: $(xe vm-param-get uuid=$vm param-name=name-description)"
    echo "other-config[xe_example] = $(xe vm-param-get uuid=$vm param-name=other-config param-key=xe_example)"
    xe vm-param-set uuid=$vm name-description="$original"
    xe vm-param-remove uuid=$vm param-name=other-config param-key=xe_example
    echo "OK: edit-vm-properties"
}
```

<details><summary>Sample output</summary>

```text
New description: Edited by the xe example
other-config[xe_example] = true
OK: edit-vm-properties
```

</details>
