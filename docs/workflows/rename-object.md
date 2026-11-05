<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Rename an object

Change an object's name and read it back — how any object is renamed.

Workflow `rename-object`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/VirtualMachines/RenameObject.cs`](../../csharp/VirtualMachines/RenameObject.cs)

```csharp
/// <summary>
/// Change an object's name and read it back — how any object is renamed.
/// </summary>
/// <example>
/// <code>
/// Workflows.RenameObject("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void RenameObject(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);
    var vm = VmByName(session, vmName);
    var original = VM.get_name_label(session, vm);
    VM.set_name_label(session, vm, "sdk-renamed");
    Console.WriteLine($"Renamed '{original}' → '{VM.get_name_label(session, vm)}'");
    VM.set_name_label(session, vm, original); // restore so the example is repeatable
    Console.WriteLine("OK: rename-object");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Renamed 'web-01'  'sdk-renamed'
OK: rename-object
```

</details>

## Python

Source: [`python/virtual_machines/rename_object.py`](../../python/virtual_machines/rename_object.py)

```python
"""Rename an object.

Change an object's name and read it back — how any object is renamed.

Run it::

    rename_object("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def rename_object(url, username, password, vm_name):
    """Rename the named VM, then restore its original name so the example is repeatable."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    original = session.xenapi.VM.get_name_label(vm)
    session.xenapi.VM.set_name_label(vm, "sdk-renamed")
    print("Renamed '%s' -> '%s'" % (original, session.xenapi.VM.get_name_label(vm)))
    session.xenapi.VM.set_name_label(vm, original)  # restore so the example is repeatable
    print("OK: rename-object")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Renamed 'web-01' -> 'sdk-renamed'
OK: rename-object
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/RenameObject.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/RenameObject.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class RenameObject {
    private RenameObject() {
    }

    /**
     * Rename an object.
     *
     * <p>Change an object's name and read it back — how any object is renamed.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * RenameObject.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);
        String original = vm.getNameLabel(conn);
        vm.setNameLabel(conn, "sdk-renamed");
        System.out.println("Renamed '" + original + "' → '" + vm.getNameLabel(conn) + "'");
        vm.setNameLabel(conn, original); // restore so the example is repeatable
        System.out.println("OK: rename-object");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Renamed 'web-01' ? 'sdk-renamed'
OK: rename-object
```

</details>

## Go

Source: [`go/rename_object.go`](../../go/rename_object.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// renameObject - Rename an object.
//
// Change an object's name and read it back — how any object is renamed.
//
// Run it:
//
//	renameObject("https://xenserver", "root", password, "web-01")
func renameObject(url, user, password, vmName string) {
	session := connect(url, user, password)
	vm := vmByName(session, vmName)
	original, _ := xenapi.VM.GetNameLabel(session, vm)
	check(xenapi.VM.SetNameLabel(session, vm, "sdk-renamed"))
	now, _ := xenapi.VM.GetNameLabel(session, vm)
	fmt.Printf("Renamed '%s' -> '%s'\n", original, now)
	check(xenapi.VM.SetNameLabel(session, vm, original)) // restore so the example is repeatable
	fmt.Println("OK: rename-object")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Renamed 'web-01' -> 'sdk-renamed'
OK: rename-object
```

</details>

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-RenameObject.ps1`](../../powershell/VirtualMachines/Invoke-RenameObject.ps1)

```powershell
function Invoke-RenameObject {
    <#
    .SYNOPSIS
        Rename an object.
    .DESCRIPTION
        Change an object's name and read it back — how any object is renamed.
    .EXAMPLE
        Invoke-RenameObject -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $original = $vm.name_label

    $vm | Set-XenVM -NameLabel "sdk-renamed"
    Write-Host "Renamed '$original' -> '$((Get-XenVM -Ref $vm.opaque_ref).name_label)'"

    $vm | Set-XenVM -NameLabel $original  # restore so the example is repeatable
    Write-Host "OK: rename-object"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Renamed 'web-01' -> 'sdk-renamed'
OK: rename-object
```

</details>

## xe CLI

Source: [`cli/virtual-machines/rename-object.sh`](../../cli/virtual-machines/rename-object.sh)

```bash
# Rename an object.
#
# Change an object's name and read it back — how any object is renamed.
#
# Run it:
#   ./workflows.sh rename-object https://xenserver root "$password"

rename_object() {
    vm=$(vm_uuid web-01)
    original=$(xe vm-param-get uuid=$vm param-name=name-label)
    xe vm-param-set uuid=$vm name-label=xe-renamed
    echo "Renamed '$original' -> '$(xe vm-param-get uuid=$vm param-name=name-label)'"
    xe vm-param-set uuid=$vm name-label="$original"   # restore so the example is repeatable
    echo "OK: rename-object"
}
```

<details><summary>Example output</summary>

```text
Renamed 'web-01' -> 'xe-renamed'
OK: rename-object
```

</details>
