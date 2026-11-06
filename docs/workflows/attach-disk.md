<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Attach a new disk

Create a fresh virtual disk on a storage repository and attach it to a VM.

Workflow `attach-disk`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Storage/Invoke-AttachDisk.ps1`](../../powershell/Storage/Invoke-AttachDisk.ps1)

```powershell
function Invoke-AttachDisk {
    <#
    .SYNOPSIS
        Attach a new disk.
    .DESCRIPTION
        Create a fresh virtual disk on a storage repository and attach it to a VM.
    .EXAMPLE
        Invoke-AttachDisk -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8' -SrName 'Shared NFS'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [Parameter(Mandatory = $true)][string]$SrName,
        [string]$NewVmName = "sdk-example-attachdisk"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm
    $ref = $vm
    $sr = Get-XenSR -Name $SrName | Select-Object -First 1
    if (-not $sr) { throw "No SR named '$SrName' was found." }

    # Create a fresh VDI on the SR and attach it as a new VBD (a new virtual disk).
    $vdi = New-XenVDI -NameLabel "sdk-example-data-disk" -SR $sr -VirtualSize 8GB `
        -Type user -Sharable $false -ReadOnly $false -PassThru
    $device = (Get-XenVMProperty -Ref $ref -XenProperty AllowedVBDDevices)[0]
    New-XenVBD -VM (Get-XenVM -Ref $ref) -VDI $vdi -Userdevice $device -Bootable $false `
        -Mode RW -Type Disk -Empty $false | Out-Null
    Write-Host "Attached an 8 GiB disk on $($sr.name_label) as device $device"
    Write-Host "VM now has $(@((Get-XenVM -Ref $ref).VBDs).Count) VBD(s)"

    # Tidy up: destroy the VM (which removes its VBDs) and then its disks (Remove-XenVM leaves VDIs
    # behind), including the one just attached.
    Remove-VmAndDisks -Ref $ref
    Write-Host "OK: attach-disk"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Attached an 8 GiB disk on Shared NFS as device 1
VM now has 2 VBD(s)
OK: attach-disk
```

</details>

## xe CLI

Source: [`cli/storage/attach-disk.sh`](../../cli/storage/attach-disk.sh)

```bash
# Attach a new disk.
#
# Create a fresh virtual disk on a storage repository and attach it to a VM.
#
# Run it:
#   ./workflows.sh attach-disk https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)
#   sr_name (Shared NFS)

attach_disk() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-example-attachdisk)
    vdi=$(xe vdi-create sr-uuid=$(sr_by_name "$(param sr_name "Shared NFS")") name-label=xe-example-data-disk virtual-size=8GiB type=user)
    # The first device position the VM has free.
    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=allowed-VBD-devices)")")
    xe vbd-create vm-uuid=$vm vdi-uuid=$vdi device=$device type=Disk mode=RW >/dev/null
    echo "Attached an 8 GiB disk; VM now has $(count_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=VBDs)")") VBD(s)"
    # Tidy up: vm-uninstall destroys the VM and the disks it OWNS (VBD other-config:owner, which vm-install
    # sets on the template's disks) - not the one just attached, so destroy that too.
    xe vm-uninstall uuid=$vm force=true
    xe vdi-destroy uuid=$vdi
    echo "OK: attach-disk"
}
```

<details><summary>Example output</summary>

```text
Attached an 8 GiB disk; VM now has 2 VBD(s)
OK: attach-disk
```

</details>

## Python

Source: [`python/storage/attach_disk.py`](../../python/storage/attach_disk.py)

```python
"""Attach a new disk.

Create a fresh virtual disk on a storage repository and attach it to a VM.

Run it::

    attach_disk("https://xenserver", "root", password, "Rocky Linux 8", "Shared NFS")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, sr_by_name, template_by_name


def attach_disk(url, username, password, template_name, sr_name, new_vm_name="sdk-example-attachdisk"):
    """Provision a VM, then create a fresh VDI on the named SR and attach it as a new virtual disk."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    vm = session.xenapi.VM.clone(template_by_name(session, template_name), new_vm_name)
    provision(session, vm)
    sr_ref = sr_by_name(session, sr_name)

    vdi = session.xenapi.VDI.create({
        "name_label": "sdk-example-data-disk",
        "SR": sr_ref,
        "virtual_size": str(8 * GIB),
        "type": "user",
        "sharable": False,
        "read_only": False,
        "other_config": {},
    })
    device = session.xenapi.VM.get_allowed_VBD_devices(vm)[0]
    session.xenapi.VBD.create({
        "VM": vm, "VDI": vdi, "userdevice": device,
        "bootable": False,
        "mode": "RW", "type": "Disk", "empty": False, "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("Attached an 8 GiB disk on %s as device %s"
          % (session.xenapi.SR.get_name_label(sr_ref), device))
    print("VM now has %d VBD(s)" % len(session.xenapi.VM.get_VBDs(vm)))

    # Tidy up: destroy the VM (which removes its VBDs) and then its disks (VM.destroy leaves VDIs
    # behind), including the one just attached.
    destroy_vm_and_disks(session, vm)
    print("OK: attach-disk")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Attached an 8 GiB disk on Shared NFS as device 1
VM now has 2 VBD(s)
OK: attach-disk
```

</details>

## C# (.NET)

Source: [`csharp/Storage/AttachDisk.cs`](../../csharp/Storage/AttachDisk.cs)

```csharp
/// <summary>
/// Create a fresh virtual disk on a storage repository and attach it to a VM.
/// </summary>
/// <example>
/// <code>
/// Workflows.AttachDisk("https://xenserver", "root", password, "Rocky Linux 8", "Shared NFS");
/// </code>
/// </example>
public static void AttachDisk(string url, string user, string password,
    string templateName, string srName, string newVmName = "sdk-example-attachdisk")
{
    const long GiB = 1024L * 1024 * 1024;
    var session = Connect(url, user, password);
    var vm = VM.clone(session, TemplateByName(session, templateName), newVmName);
    Provision(session, vm);
    var srRef = SrByName(session, srName);

    // Create a fresh VDI on the SR and attach it as a new VBD (a new virtual disk).
    var vdi = VDI.create(session, new VDI
    {
        name_label = "sdk-example-data-disk",
        SR = srRef,
        virtual_size = 8 * GiB,
        type = vdi_type.user,
        sharable = false,
        read_only = false,
        other_config = new Dictionary<string, string>(),
    });
    var device = VM.get_allowed_VBD_devices(session, vm)[0];
    VBD.create(session, new VBD
    {
        VM = vm,
        VDI = vdi,
        userdevice = device,
        bootable = false,
        mode = vbd_mode.RW,
        type = vbd_type.Disk,
        empty = false,
        other_config = new Dictionary<string, string>(),
        qos_algorithm_type = "",
        qos_algorithm_params = new Dictionary<string, string>(),
    });
    Console.WriteLine($"Attached an 8 GiB disk on {SR.get_name_label(session, srRef)} as device {device}");
    Console.WriteLine($"VM now has {VM.get_VBDs(session, vm).Count} VBD(s)");

    // Tidy up: destroy the VM (which removes its VBDs) and then its disks (VM.destroy leaves VDIs
    // behind), including the one just attached.
    DestroyVmAndDisks(session, vm);
    Console.WriteLine("OK: attach-disk");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Attached an 8 GiB disk on Shared NFS as device 1
VM now has 2 VBD(s)
OK: attach-disk
```

</details>

## Go

Source: [`go/attach_disk.go`](../../go/attach_disk.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// attachDisk - Attach a new disk.
//
// Create a fresh virtual disk on a storage repository and attach it to a VM.
//
// Run it:
//
//	attachDisk("https://xenserver", "root", password, "Rocky Linux 8", "Shared NFS", "sdk-example-attachdisk")
func attachDisk(url, user, password, templateName, srName, newVMName string) {
	const GiB = 1024 * 1024 * 1024

	session := connect(url, user, password)
	vm, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vm)
	srRef := srByName(session, srName, false)

	// Create a fresh VDI on the SR and attach it as a new VBD (a new virtual disk).
	vdi, err := xenapi.VDI.Create(session, xenapi.VDIRecord{
		NameLabel:   "sdk-example-data-disk",
		SR:          srRef,
		VirtualSize: 8 * GiB,
		Type:        xenapi.VdiTypeUser,
		Sharable:    false,
		ReadOnly:    false,
		OtherConfig: map[string]string{},
	})
	check(err)
	devices, err := xenapi.VM.GetAllowedVBDDevices(session, vm)
	check(err)
	device := devices[0]
	_, err = xenapi.VBD.Create(session, xenapi.VBDRecord{
		VM: vm, VDI: vdi, Userdevice: device,
		Bootable: false,
		Mode:     xenapi.VbdModeRW, Type: xenapi.VbdTypeDisk, Empty: false,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
	})
	check(err)
	srLabel, _ := xenapi.SR.GetNameLabel(session, srRef)
	fmt.Printf("Attached an 8 GiB disk on %s as device %s\n", srLabel, device)
	vbds, _ := xenapi.VM.GetVBDs(session, vm)
	fmt.Printf("VM now has %d VBD(s)\n", len(vbds))

	// Tidy up: destroy the VM (which removes its VBDs) and then its disks (VM.Destroy leaves VDIs
	// behind), including the one just attached.
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: attach-disk")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Attached an 8 GiB disk on Shared NFS as device 1
VM now has 2 VBD(s)
OK: attach-disk
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/AttachDisk.java`](../../java/src/main/java/com/xenserver/samples/storage/AttachDisk.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class AttachDisk {
    private AttachDisk() {
    }

    /**
     * Attach a new disk.
     *
     * <p>Create a fresh virtual disk on a storage repository and attach it to a VM.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * AttachDisk.run("https://xenserver", "root", password, "Rocky Linux 8", "Shared NFS", "sdk-example-attachdisk");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String srName, String newVmName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm);
        SR sr = srByName(conn, srName, false);

        // Create a fresh VDI on the SR and attach it as a new VBD (a new virtual disk).
        VDI.Record vdiRec = new VDI.Record();
        vdiRec.nameLabel = "sdk-example-data-disk";
        vdiRec.SR = sr;
        vdiRec.virtualSize = 8 * GiB;
        vdiRec.type = Types.VdiType.USER;
        vdiRec.sharable = false;
        vdiRec.readOnly = false;
        vdiRec.otherConfig = new java.util.HashMap<>();
        VDI vdi = VDI.create(conn, vdiRec);

        String device = vm.getAllowedVBDDevices(conn).iterator().next();
        VBD.Record vbdRec = new VBD.Record();
        vbdRec.VM = vm;
        vbdRec.VDI = vdi;
        vbdRec.userdevice = device;
        vbdRec.bootable = false;
        vbdRec.mode = Types.VbdMode.RW;
        vbdRec.type = Types.VbdType.DISK;
        vbdRec.empty = false;
        vbdRec.otherConfig = new java.util.HashMap<>();
        vbdRec.qosAlgorithmType = "";
        vbdRec.qosAlgorithmParams = new java.util.HashMap<>();
        VBD.create(conn, vbdRec);
        System.out.println("Attached an 8 GiB disk on " + sr.getNameLabel(conn) + " as device " + device);
        System.out.println("VM now has " + vm.getVBDs(conn).size() + " VBD(s)");

        // Tidy up: the VM and both the disk it was provisioned with and the one just attached.
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: attach-disk");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Attached an 8 GiB disk on Shared NFS as device 11
VM now has 2 VBD(s)
OK: attach-disk
```

</details>
