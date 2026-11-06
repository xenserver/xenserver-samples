<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create a VM from a template

Clone one of the built-in templates and provision the clone into a real, installable VM.

Workflow `create-vm`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-CreateVm.ps1`](../../powershell/VirtualMachines/Invoke-CreateVm.ps1)

```powershell
function Invoke-CreateVm {
    <#
    .SYNOPSIS
        Create a VM from a template.
    .DESCRIPTION
        Clone one of the built-in templates and provision the clone into a real, installable VM.
    .EXAMPLE
        Invoke-CreateVm -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-vm"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    Write-Host "Using template: $($template.name_label)"

    # Pipe the template straight into the Clone action; -PassThru returns the new VM object.
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Write-Host "Cloned new VM: $($vm.uuid)"

    Invoke-VmProvision -Ref $vm.opaque_ref
    Write-Host "Provisioned. is_a_template = $((Get-XenVM -Ref $vm.opaque_ref).is_a_template)"

    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "Cleaned up the example VM."

    Write-Host "OK: create-vm"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Using template: Rocky Linux 8
Cloned new VM: 00000001-0000-0000-ee09-000000000000
Provisioned. is_a_template = False
Cleaned up the example VM.
OK: create-vm
```

</details>

## xe CLI

Source: [`cli/virtual-machines/create-vm.sh`](../../cli/virtual-machines/create-vm.sh)

```bash
# Create a VM from a template.
#
# Clone one of the built-in templates and provision the clone into a real, installable VM.
#
# Run it:
#   ./workflows.sh create-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

create_vm() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-example-vm)
    echo "Created VM: $vm"
    echo "is-a-template = $(xe vm-param-get uuid=$vm param-name=is-a-template)"
    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it owns (vm-destroy
    # would leave the disks behind).
    xe vm-uninstall uuid=$vm force=true
    echo "OK: create-vm"
}
```

<details><summary>Example output</summary>

```text
Created VM: 00000001-0000-0000-f209-000000000000
is-a-template = false
OK: create-vm
```

</details>

## Python

Source: [`python/virtual_machines/create_vm.py`](../../python/virtual_machines/create_vm.py)

```python
"""Create a VM from a template.

Clone one of the built-in templates and provision the clone into a real, installable VM.

Run it::

    create_vm("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, template_by_name


def create_vm(url, username, password, template_name, new_vm_name="sdk-example-vm"):
    """Clone the named template and provision it into a real, installable VM."""
    session = connect(url, username, password)
    template_ref = template_by_name(session, template_name)
    print("Using template: %s" % session.xenapi.VM.get_name_label(template_ref))

    vm_ref = session.xenapi.VM.clone(template_ref, new_vm_name)
    print("Cloned new VM: %s" % session.xenapi.VM.get_uuid(vm_ref))

    # provision() turns the template clone into a normal (installable) VM.
    provision(session, vm_ref)
    print("Provisioned. is_a_template = %s" % session.xenapi.VM.get_is_a_template(vm_ref))

    # Tidy up so the example is repeatable.
    destroy_vm_and_disks(session, vm_ref)
    print("Cleaned up the example VM.")

    print("OK: create-vm")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Using template: Rocky Linux 8
Cloned new VM: 00000001-0000-0000-f009-000000000000
Provisioned. is_a_template = False
Cleaned up the example VM.
OK: create-vm
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/CreateVm.cs`](../../csharp/VirtualMachines/CreateVm.cs)

```csharp
/// <summary>
/// Clone one of the built-in templates and provision the clone into a real, installable VM.
/// </summary>
/// <example>
/// <code>
/// Workflows.CreateVm("https://xenserver", "root", password, "Rocky Linux 8");
/// </code>
/// </example>
public static void CreateVm(string url, string user, string password,
    string templateName, string newVmName = "sdk-example-vm")
{
    var session = Connect(url, user, password);
    var templateRef = TemplateByName(session, templateName);
    Console.WriteLine($"Using template: {VM.get_name_label(session, templateRef)}");

    var vmRef = VM.clone(session, templateRef, newVmName);
    Console.WriteLine($"Cloned new VM: {VM.get_uuid(session, vmRef.opaque_ref)}");

    Provision(session, vmRef.opaque_ref);
    Console.WriteLine($"Provisioned. is_a_template = {VM.get_is_a_template(session, vmRef.opaque_ref)}");

    DestroyVmAndDisks(session, vmRef.opaque_ref);
    Console.WriteLine("Cleaned up the example VM.");

    Console.WriteLine("OK: create-vm");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Using template: Rocky Linux 8
Cloned new VM: 00000001-0000-0000-ee09-000000000000
Provisioned. is_a_template = False
Cleaned up the example VM.
OK: create-vm
```

</details>

## Go

Source: [`go/create_vm.go`](../../go/create_vm.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// createVM - Create a VM from a template.
//
// Clone one of the built-in templates and provision the clone into a real, installable VM.
//
// Run it:
//
//	createVM("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vm")
func createVM(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	templateRef := templateByName(session, templateName)
	name, _ := xenapi.VM.GetNameLabel(session, templateRef)
	fmt.Printf("Using template: %s\n", name)

	vmRef, err := xenapi.VM.Clone(session, templateRef, newVMName)
	check(err)
	uuid, _ := xenapi.VM.GetUUID(session, vmRef)
	fmt.Printf("Cloned new VM: %s\n", uuid)

	provision(session, vmRef)
	isTemplate, _ := xenapi.VM.GetIsATemplate(session, vmRef)
	fmt.Printf("Provisioned. is_a_template = %v\n", isTemplate)

	destroyVMAndDisks(session, vmRef)
	fmt.Println("Cleaned up the example VM.")

	fmt.Println("OK: create-vm")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Using template: Rocky Linux 8
Cloned new VM: 00000001-0000-0000-eb09-000000000000
Provisioned. is_a_template = false
Cleaned up the example VM.
OK: create-vm
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/CreateVm.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/CreateVm.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateVm {
    private CreateVm() {
    }

    /**
     * Create a VM from a template.
     *
     * <p>Clone one of the built-in templates and provision the clone into a real, installable VM.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateVm.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vm");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM template = templateByName(conn, templateName);
        System.out.println("Using template: " + template.getNameLabel(conn));

        VM vm = template.createClone(conn, newVmName);
        System.out.println("Cloned new VM: " + vm.getUuid(conn));

        provision(conn, vm);
        System.out.println("Provisioned. is_a_template = " + vm.getIsATemplate(conn));

        destroyVmAndDisks(conn, vm);
        System.out.println("Cleaned up the example VM.");

        System.out.println("OK: create-vm");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Using template: Rocky Linux 8
Cloned new VM: 00000001-0000-0000-eb09-000000000000
Provisioned. is_a_template = false
Cleaned up the example VM.
OK: create-vm
```

</details>
