<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Convert a VM to a template

Turn a VM into a reusable custom template. This is a one-way operation.

Workflow `convert-to-template`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-ConvertToTemplate.ps1`](../../powershell/VirtualMachines/Invoke-ConvertToTemplate.ps1)

```powershell
function Invoke-ConvertToTemplate {
    <#
    .SYNOPSIS
        Convert a VM to a template.
    .DESCRIPTION
        Turn a VM into a reusable custom template. This is a one-way operation.
    .EXAMPLE
        Invoke-ConvertToTemplate -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-totemplate"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm.opaque_ref  # now a real (halted) VM
    $ref = $vm.opaque_ref
    Write-Host "is_a_template after provision: $((Get-XenVM -Ref $ref).is_a_template)"

    # Converting a VM to a custom template is a one-way operation.
    $vm | Set-XenVM -IsATemplate $true
    Write-Host "is_a_template after convert:  $((Get-XenVM -Ref $ref).is_a_template)"

    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "OK: convert-to-template"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
is_a_template after provision: False
is_a_template after convert:  True
OK: convert-to-template
```

</details>

## xe CLI

Source: [`cli/virtual-machines/convert-to-template.sh`](../../cli/virtual-machines/convert-to-template.sh)

```bash
# Convert a VM to a template.
#
# Turn a VM into a reusable custom template. This is a one-way operation.
#
# Run it:
#   ./workflows.sh convert-to-template https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

convert_to_template() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-example-totemplate)
    echo "is-a-template after install: $(xe vm-param-get uuid=$vm param-name=is-a-template)"
    xe vm-param-set uuid=$vm is-a-template=true   # one-way operation
    echo "is-a-template after convert: $(xe vm-param-get uuid=$vm param-name=is-a-template)"
    # It is a template now, so template-uninstall removes it and the disks it owns.
    xe template-uninstall template-uuid=$vm force=true
    echo "OK: convert-to-template"
}
```

<details><summary>Example output</summary>

```text
is-a-template after install: false
is-a-template after convert: true
OK: convert-to-template
```

</details>

## Python

Source: [`python/virtual_machines/convert_to_template.py`](../../python/virtual_machines/convert_to_template.py)

```python
"""Convert a VM to a template.

Turn a VM into a reusable custom template. This is a one-way operation.

Run it::

    convert_to_template("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, template_by_name


def convert_to_template(url, username, password, template_name, new_vm_name="sdk-example-totemplate"):
    """Provision a real VM, convert it into a custom template, then destroy it."""
    session = connect(url, username, password)
    vm = session.xenapi.VM.clone(template_by_name(session, template_name), new_vm_name)
    provision(session, vm)  # now a real (halted) VM
    print("is_a_template after provision: %s" % session.xenapi.VM.get_is_a_template(vm))

    # Converting a VM to a custom template is a one-way operation.
    session.xenapi.VM.set_is_a_template(vm, True)
    print("is_a_template after convert:  %s" % session.xenapi.VM.get_is_a_template(vm))

    destroy_vm_and_disks(session, vm)
    print("OK: convert-to-template")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
is_a_template after provision: False
is_a_template after convert:  True
OK: convert-to-template
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/ConvertToTemplate.cs`](../../csharp/VirtualMachines/ConvertToTemplate.cs)

```csharp
/// <summary>
/// Turn a VM into a reusable custom template. This is a one-way operation.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConvertToTemplate("https://xenserver", "root", password, "Rocky Linux 8");
/// </code>
/// </example>
public static void ConvertToTemplate(string url, string user, string password,
    string templateName, string newVmName = "sdk-example-totemplate")
{
    var session = Connect(url, user, password);
    var vm = VM.clone(session, TemplateByName(session, templateName), newVmName).opaque_ref;
    Provision(session, vm); // now a real (halted) VM
    Console.WriteLine($"is_a_template after provision: {VM.get_is_a_template(session, vm)}");

    // Converting a VM to a custom template is a one-way operation.
    VM.set_is_a_template(session, vm, true);
    Console.WriteLine($"is_a_template after convert:  {VM.get_is_a_template(session, vm)}");

    DestroyVmAndDisks(session, vm);
    Console.WriteLine("OK: convert-to-template");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
is_a_template after provision: False
is_a_template after convert:  True
OK: convert-to-template
```

</details>

## Go

Source: [`go/convert_to_template.go`](../../go/convert_to_template.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// convertToTemplate - Convert a VM to a template.
//
// Turn a VM into a reusable custom template. This is a one-way operation.
//
// Run it:
//
//	convertToTemplate("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-totemplate")
func convertToTemplate(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	vm, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vm) // now a real (halted) VM
	isTemplate, _ := xenapi.VM.GetIsATemplate(session, vm)
	fmt.Printf("is_a_template after provision: %v\n", isTemplate)

	// Converting a VM to a custom template is a one-way operation.
	check(xenapi.VM.SetIsATemplate(session, vm, true))
	isTemplate, _ = xenapi.VM.GetIsATemplate(session, vm)
	fmt.Printf("is_a_template after convert:  %v\n", isTemplate)

	destroyVMAndDisks(session, vm)
	fmt.Println("OK: convert-to-template")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
is_a_template after provision: false
is_a_template after convert:  true
OK: convert-to-template
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/ConvertToTemplate.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/ConvertToTemplate.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class ConvertToTemplate {
    private ConvertToTemplate() {
    }

    /**
     * Convert a VM to a template.
     *
     * <p>Turn a VM into a reusable custom template. This is a one-way operation.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConvertToTemplate.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-totemplate");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm); // now a real (halted) VM
        System.out.println("is_a_template after provision: " + vm.getIsATemplate(conn));

        // Converting a VM to a custom template is a one-way operation.
        vm.setIsATemplate(conn, true);
        System.out.println("is_a_template after convert:  " + vm.getIsATemplate(conn));

        destroyVmAndDisks(conn, vm);
        System.out.println("OK: convert-to-template");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
is_a_template after provision: false
is_a_template after convert:  true
OK: convert-to-template
```

</details>
