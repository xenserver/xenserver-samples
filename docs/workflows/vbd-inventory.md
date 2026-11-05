<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Inventory a VM's disks

List a VM's attached disks and the size of each.

Workflow `vbd-inventory`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Storage/VbdInventory.cs`](../../csharp/Storage/VbdInventory.cs)

```csharp
/// <summary>
/// List a VM's attached disks and the size of each.
/// </summary>
/// <example>
/// <code>
/// Workflows.VbdInventory("https://xenserver", "root", password, "db-01");
/// </code>
/// </example>
public static void VbdInventory(string url, string user, string password, string vmName)
{
    const long GiB = 1024L * 1024 * 1024;
    var session = Connect(url, user, password);
    var vm = VmByName(session, vmName);
    Console.WriteLine($"Disks of '{VM.get_name_label(session, vm)}':");
    foreach (var vbdRef in VM.get_VBDs(session, vm))
    {
        var vbd = VBD.get_record(session, vbdRef.opaque_ref);
        if (vbd.type != vbd_type.Disk) continue;
        var vdi = VBD.get_VDI(session, vbdRef.opaque_ref).opaque_ref;
        var size = vdi == "OpaqueRef:NULL" ? 0 : VDI.get_virtual_size(session, vdi) / GiB;
        Console.WriteLine($"  - device {vbd.userdevice}: {size} GiB");
    }
    Console.WriteLine("OK: vbd-inventory");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Disks of 'db-01':
  - device 0: 25 GiB
OK: vbd-inventory
```

</details>

## Python

Source: [`python/storage/vbd_inventory.py`](../../python/storage/vbd_inventory.py)

```python
"""Inventory a VM's disks.

List a VM's attached disks and the size of each.

Run it::

    vbd_inventory("https://xenserver", "root", password, "db-01")
"""

from connection import connect
from helpers import vm_by_name


def vbd_inventory(url, username, password, vm_name):
    """List the named VM's disk VBDs and the size of each backing VDI."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    print("Disks of '%s':" % session.xenapi.VM.get_name_label(vm))
    for vbd in session.xenapi.VM.get_VBDs(vm):
        if session.xenapi.VBD.get_type(vbd) != "Disk":
            continue
        vdi = session.xenapi.VBD.get_VDI(vbd)
        size = 0 if vdi == "OpaqueRef:NULL" else int(session.xenapi.VDI.get_virtual_size(vdi)) // GIB
        print("  - device %s: %d GiB" % (session.xenapi.VBD.get_userdevice(vbd), size))
    print("OK: vbd-inventory")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Disks of 'db-01':
  - device 0: 25 GiB
OK: vbd-inventory
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/VbdInventory.java`](../../java/src/main/java/com/xenserver/samples/storage/VbdInventory.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class VbdInventory {
    private VbdInventory() {
    }

    /**
     * Inventory a VM's disks.
     *
     * <p>List a VM's attached disks and the size of each.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * VbdInventory.run("https://xenserver", "root", password, "db-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);
        System.out.println("Disks of '" + vm.getNameLabel(conn) + "':");
        for (VBD vbd : vm.getVBDs(conn)) {
            VBD.Record rec = vbd.getRecord(conn);
            if (rec.type != Types.VbdType.DISK) continue;
            VDI vdi = vbd.getVDI(conn);
            long size = vdi.toWireString().equals("OpaqueRef:NULL") ? 0 : vdi.getVirtualSize(conn) / GiB;
            System.out.println("  - device " + rec.userdevice + ": " + size + " GiB");
        }
        System.out.println("OK: vbd-inventory");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Disks of 'db-01':
  - device 0: 25 GiB
OK: vbd-inventory
```

</details>

## Go

Source: [`go/vbd_inventory.go`](../../go/vbd_inventory.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// vbdInventory - Inventory a VM's disks.
//
// List a VM's attached disks and the size of each.
//
// Run it:
//
//	vbdInventory("https://xenserver", "root", password, "db-01")
func vbdInventory(url, user, password, vmName string) {
	const GiB = 1024 * 1024 * 1024

	session := connect(url, user, password)
	vm := vmByName(session, vmName)
	name, _ := xenapi.VM.GetNameLabel(session, vm)
	fmt.Printf("Disks of '%s':\n", name)
	vbds, err := xenapi.VM.GetVBDs(session, vm)
	check(err)
	for _, vbdRef := range vbds {
		vbd, err := xenapi.VBD.GetRecord(session, vbdRef)
		check(err)
		if vbd.Type != xenapi.VbdTypeDisk {
			continue
		}
		vdi, _ := xenapi.VBD.GetVDI(session, vbdRef)
		var size int64
		if vdi != xenapi.VDIRef("OpaqueRef:NULL") {
			virtualSize, _ := xenapi.VDI.GetVirtualSize(session, vdi)
			size = virtualSize / GiB
		}
		fmt.Printf("  - device %s: %d GiB\n", vbd.Userdevice, size)
	}
	fmt.Println("OK: vbd-inventory")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Disks of 'db-01':
  - device 0: 25 GiB
OK: vbd-inventory
```

</details>

## PowerShell

Source: [`powershell/Storage/Invoke-VbdInventory.ps1`](../../powershell/Storage/Invoke-VbdInventory.ps1)

```powershell
function Invoke-VbdInventory {
    <#
    .SYNOPSIS
        Inventory a VM's disks.
    .DESCRIPTION
        List a VM's attached disks and the size of each.
    .EXAMPLE
        Invoke-VbdInventory -Url https://xenserver -UserName root -Password $password -VmName 'db-01'
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
    Write-Host "Disks of '$($vm.name_label)':"
    (Get-XenVM -Ref $vm.opaque_ref).VBDs |
        ForEach-Object { Get-XenVBD -Ref $_.opaque_ref } |
        Where-Object { $_.type -eq 'Disk' } |
        ForEach-Object {
            $vdiRef = $_.VDI.opaque_ref
            $size = if ($vdiRef -eq 'OpaqueRef:NULL') { 0 } else { [long]((Get-XenVDI -Ref $vdiRef).virtual_size / 1GB) }
            Write-Host "  - device $($_.userdevice): $size GiB"
        }
    Write-Host "OK: vbd-inventory"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Disks of 'db-01':
  - device 0: 25 GiB
OK: vbd-inventory
```

</details>

## xe CLI

Source: [`cli/storage/vbd-inventory.sh`](../../cli/storage/vbd-inventory.sh)

```bash
# Inventory a VM's disks.
#
# List a VM's attached disks and the size of each.
#
# Run it:
#   ./workflows.sh vbd-inventory https://xenserver root "$password"

vbd_inventory() {
    vm=$(vm_uuid db-01)
    echo "Disks of db-01:"
    vbds=$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=VBDs)")
    for vbd in ${vbds//,/ }; do
        if [ "$(xe vbd-param-get uuid=$vbd param-name=type)" = "Disk" ]; then
            vdi=$(xe vbd-param-get uuid=$vbd param-name=vdi-uuid)
            echo "  - device $(xe vbd-param-get uuid=$vbd param-name=userdevice): $(xe vdi-param-get uuid=$vdi param-name=virtual-size) bytes"
        fi
    done
    echo "OK: vbd-inventory"
}
```

<details><summary>Example output</summary>

```text
Disks of db-01:
  - device 0: 26843545600 bytes
OK: vbd-inventory
```

</details>
