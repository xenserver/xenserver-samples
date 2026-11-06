<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage VM disks

Deactivate a running VM's disk, resize it, reactivate it — the Activate/Deactivate and Resize operations from the VM's Storage tab.

Workflow `manage-vm-disks`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-ManageVmDisks.ps1`](../../powershell/VirtualMachines/Invoke-ManageVmDisks.ps1)

```powershell
function Invoke-ManageVmDisks {
    <#
    .SYNOPSIS
        Manage VM disks.
    .DESCRIPTION
        Deactivate a running VM's disk, resize it, reactivate it — the Activate/Deactivate and Resize
        operations from the VM's Storage tab.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [Parameter(Mandatory = $true)][string]$SrName,
        [string]$NewVmName = "sdk-example-vm-disks"
    )
    # Not the VM's root/boot disk: a real VM's system disk is Unpluggable=false (only a template's
    # non-system disks default to unpluggable), so Unplug on it fails on a real host with
    # VBD_NOT_UNPLUGGABLE - and the VM has to be running in the first place, or unplug fails with
    # VM_BAD_POWER_STATE. Work on a data disk this example adds to its own throwaway VM instead,
    # and tidy up afterwards so the example is repeatable. No shrink: real SR backends refuse one
    # outright (SR_BACKEND_FAILURE_79), so this only ever grows.
    #
    # Plugging and unplugging a disk on a running VM needs the guest's PV drivers
    # (VM_MISSING_PV_DRIVERS otherwise), so the VM is a throwaway copy of SourceVm, a VM with a guest OS
    # and PV drivers.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm.opaque_ref
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref

    $sr = Get-XenSR -Name $SrName | Select-Object -First 1
    if (-not $sr) { throw "No SR named '$SrName' was found." }
    $vdi = New-XenVDI -NameLabel "sdk-example-data-disk" -SR $sr -VirtualSize 4GB `
        -Type user -Sharable $false -ReadOnly $false -PassThru
    $device = (Get-XenVMProperty -Ref $ref -XenProperty AllowedVBDDevices)[0]
    $vbd = New-XenVBD -VM (Get-XenVM -Ref $ref) -VDI $vdi -Userdevice $device -Bootable $false `
        -Mode RW -Type Disk -Empty $false -PassThru
    $vbd | Invoke-XenVBD -XenAction Plug
    Write-Host "Disk attached:  $((Get-XenVBD -Ref $vbd.opaque_ref).currently_attached)"

    # Deactivate = VBD.unplug. The disk stays with the VM; it is just no longer live.
    Invoke-XenVBD -Ref $vbd.opaque_ref -XenAction Unplug
    Write-Host "After unplug:   $((Get-XenVBD -Ref $vbd.opaque_ref).currently_attached)"

    $size = (Get-XenVDI -Ref $vdi.opaque_ref).virtual_size
    Invoke-XenVDI -Ref $vdi.opaque_ref -XenAction Resize -Size ([int64]$size * 2)
    Write-Host "Resized:        $size -> $((Get-XenVDI -Ref $vdi.opaque_ref).virtual_size) bytes"

    Invoke-XenVBD -Ref $vbd.opaque_ref -XenAction Plug
    Write-Host "After plug:     $((Get-XenVBD -Ref $vbd.opaque_ref).currently_attached)"

    # Growing a disk that is attached and live is a DIFFERENT action, not a flag on the same one:
    # ResizeOnline tells the storage layer the guest is using the disk while it grows. Only some
    # storage drivers can (none of a stock XenServer 9's do), and the rest refuse with
    # SR_OPERATION_NOT_SUPPORTED - so ask the SR's driver (its SM record's features) first.
    $srType = (Get-XenSR -Ref $sr.opaque_ref).type
    $features = (Get-XenSM | Where-Object { $_.type -eq $srType } | Select-Object -First 1).features
    if ($features -and $features.ContainsKey("VDI_RESIZE_ONLINE")) {
        $grown = [int64](Get-XenVDI -Ref $vdi.opaque_ref).virtual_size + 1GB
        Invoke-XenVDI -Ref $vdi.opaque_ref -XenAction ResizeOnline -Size $grown
        Write-Host "Grown online:   $((Get-XenVDI -Ref $vdi.opaque_ref).virtual_size) bytes"
    }
    else {
        Write-Host "Grown online:   not supported by $srType storage; unplug, resize, plug as above"
    }

    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $ref
    Write-Host "OK: manage-vm-disks"
    Disconnect-XenServer -Session $session
}
```

<details><summary>Example output</summary>

```text
Disk attached:  True
After unplug:   False
Resized:        4294967296 -> 8589934592 bytes
After plug:     True
Grown online:   not supported by nfs storage; unplug, resize, plug as above
OK: manage-vm-disks
```

</details>

## xe CLI

Source: [`cli/virtual-machines/manage-vm-disks.sh`](../../cli/virtual-machines/manage-vm-disks.sh)

```bash
# Manage VM disks.
#
# Deactivate a running VM's disk, resize it, reactivate it — the Activate/Deactivate and Resize operations
# from the VM's Storage tab.
#
# Run it:
#   ./workflows.sh manage-vm-disks https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)
#   sr_name (Shared NFS)

# Not the VM's root/boot disk: a real VM's system disk is unpluggable=false (only a template's non-system
# disks default to unpluggable), so vbd-unplug on it fails on a real host with VBD_NOT_UNPLUGGABLE - and
# the VM has to be running in the first place, or unplug fails with VM_BAD_POWER_STATE. Work on a data
# disk this example adds to its own throwaway VM instead, and tidy up afterwards so the example is
# repeatable. No shrink: real SR backends refuse one outright (SR_BACKEND_FAILURE_79), so this only ever
# grows.
#
# Plugging and unplugging a disk on a running VM needs the guest's PV drivers (VM_MISSING_PV_DRIVERS
# otherwise), so the VM is a throwaway copy of source_vm, a VM with a guest OS and PV drivers.
manage_vm_disks() {
    local source_vm sr_name sr device sr_type sm
    source_vm=$(param source_vm "web-01")
    sr_name=$(param sr_name "Shared NFS")
    sr=$(first_csv "$(xe sr-list name-label="$sr_name" --minimal)")
    vm=$(copy_of_guest "$source_vm" "xe-example-vm-disks")
    xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"

    vdi=$(xe vdi-create sr-uuid=$sr name-label=xe-example-data-disk virtual-size=4GiB type=user)
    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=allowed-VBD-devices)")")
    vbd=$(xe vbd-create vm-uuid=$vm vdi-uuid=$vdi device=$device type=Disk mode=RW)
    xe vbd-plug uuid=$vbd
    echo "Disk attached:  $(xe vbd-param-get uuid=$vbd param-name=currently-attached)"

    # Deactivate: the disk stays with the VM, it is just no longer live.
    xe vbd-unplug uuid=$vbd
    echo "After unplug:   $(xe vbd-param-get uuid=$vbd param-name=currently-attached)"

    size=$(xe vdi-param-get uuid=$vdi param-name=virtual-size)
    xe vdi-resize uuid=$vdi disk-size=$((size * 2))
    echo "Resized:        $size -> $(xe vdi-param-get uuid=$vdi param-name=virtual-size) bytes"

    xe vbd-plug uuid=$vbd
    echo "After plug:     $(xe vbd-param-get uuid=$vbd param-name=currently-attached)"

    # Growing a disk that is attached and live is a DIFFERENT call, not a flag on the same one: online=true
    # tells the storage layer the guest is using the disk while it grows. Only some storage drivers can
    # (none of a stock XenServer 9's do), and the rest refuse with SR_OPERATION_NOT_SUPPORTED - so ask the
    # SR's driver (its SM record's features) first.
    sr_type=$(xe sr-param-get uuid=$sr param-name=type)
    sm=$(first_csv "$(xe sm-list type=$sr_type --minimal)")
    if [ -n "$sm" ] && xe sm-param-get uuid=$sm param-name=features param-key=VDI_RESIZE_ONLINE >/dev/null 2>&1; then
        grown=$(( $(xe vdi-param-get uuid=$vdi param-name=virtual-size) + 1073741824 ))
        xe vdi-resize uuid=$vdi disk-size=$grown online=true
        echo "Grown online:   $(xe vdi-param-get uuid=$vdi param-name=virtual-size) bytes"
    else
        echo "Grown online:   not supported by $sr_type storage; unplug, resize, plug as above"
    fi

    # Tidy up so the example is repeatable. vm-uninstall destroys the VM and only the disks it OWNS (VBD
    # other-config:owner, which vm-install sets) - not one attached later with a plain vbd-create, so
    # destroy the data disk too.
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    xe vdi-destroy uuid=$vdi
    echo "OK: manage-vm-disks"
}
```

<details><summary>Example output</summary>

```text
Disk attached:  true
After unplug:   false
Resized:        4294967296 -> 8589934592 bytes
After plug:     true
Grown online:   not supported by nfs storage; unplug, resize, plug as above
OK: manage-vm-disks
```

</details>

## Python

Source: [`python/virtual_machines/manage_vm_disks.py`](../../python/virtual_machines/manage_vm_disks.py)

```python
"""Manage VM disks.

Deactivate a running VM's disk, resize it, reactivate it — the Activate/Deactivate and Resize
operations from the VM's Storage tab.
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, sr_by_name, wait_for_guest_agent


def manage_vm_disks(url, username, password, source_vm, sr_name, new_vm_name="sdk-example-vm-disks"):
    """Deactivate a data disk, resize it, and reactivate it.

    Not the VM's root/boot disk: a real VM's system disk is unpluggable=false (only a template's
    non-system disks default to unpluggable), so VBD.unplug on it fails on a real host with
    VBD_NOT_UNPLUGGABLE - and the VM has to be running in the first place, or unplug fails with
    VM_BAD_POWER_STATE. Work on a data disk this example adds to its own throwaway VM instead, and
    tidy up afterwards so the example is repeatable. No shrink: real SR backends refuse one
    outright (SR_BACKEND_FAILURE_79), so this only ever grows.

    Plugging and unplugging a disk on a running VM needs the guest's PV drivers
    (VM_MISSING_PV_DRIVERS otherwise), so the VM is a throwaway copy of source_vm, a VM with a
    guest OS and PV drivers."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    vm_ref = copy_of_guest(session, source_vm, new_vm_name)
    session.xenapi.VM.start(vm_ref, False, True)
    wait_for_guest_agent(session, vm_ref)

    sr_ref = sr_by_name(session, sr_name)
    vdi_ref = session.xenapi.VDI.create({
        "name_label": "sdk-example-data-disk", "SR": sr_ref, "virtual_size": str(4 * GIB),
        "type": "user", "sharable": False, "read_only": False, "other_config": {},
    })
    vbd_ref = session.xenapi.VBD.create({
        "VM": vm_ref, "VDI": vdi_ref,
        "userdevice": session.xenapi.VM.get_allowed_VBD_devices(vm_ref)[0],
        "bootable": False,
        "mode": "RW", "type": "Disk", "empty": False, "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    session.xenapi.VBD.plug(vbd_ref)
    print("Disk attached:  %s" % session.xenapi.VBD.get_currently_attached(vbd_ref))

    # Deactivate = VBD.unplug. The disk stays with the VM; it is just no longer live.
    session.xenapi.VBD.unplug(vbd_ref)
    print("After unplug:   %s" % session.xenapi.VBD.get_currently_attached(vbd_ref))

    size = int(session.xenapi.VDI.get_virtual_size(vdi_ref))
    session.xenapi.VDI.resize(vdi_ref, str(size * 2))
    print("Resized:        %d -> %s bytes" % (size, session.xenapi.VDI.get_virtual_size(vdi_ref)))

    session.xenapi.VBD.plug(vbd_ref)
    print("After plug:     %s" % session.xenapi.VBD.get_currently_attached(vbd_ref))

    # Growing a disk that is attached and live is a DIFFERENT call, not a flag on the same one:
    # resize_online tells the storage layer the guest is using the disk while it grows. Only some
    # storage drivers can (none of a stock XenServer 9's do), and the rest refuse with
    # SR_OPERATION_NOT_SUPPORTED - so ask the SR's driver (its SM record's features) first.
    sr_type = session.xenapi.SR.get_type(sr_ref)
    features = next((r["features"] for r in session.xenapi.SM.get_all_records().values()
                     if r["type"] == sr_type), {})
    if "VDI_RESIZE_ONLINE" in features:
        grown = int(session.xenapi.VDI.get_virtual_size(vdi_ref)) + GIB
        session.xenapi.VDI.resize_online(vdi_ref, str(grown))
        print("Grown online:   %s bytes" % session.xenapi.VDI.get_virtual_size(vdi_ref))
    else:
        print("Grown online:   not supported by %s storage; unplug, resize, plug as above" % sr_type)

    session.xenapi.VM.hard_shutdown(vm_ref)
    destroy_vm_and_disks(session, vm_ref)
    print("OK: manage-vm-disks")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Disk attached:  True
After unplug:   False
Resized:        4294967296 -> 8589934592 bytes
After plug:     True
Grown online:   not supported by nfs storage; unplug, resize, plug as above
OK: manage-vm-disks
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/ManageVmDisks.cs`](../../csharp/VirtualMachines/ManageVmDisks.cs)

```csharp
/// <summary>
/// Deactivate a running VM's disk, resize it, reactivate it — the Activate/Deactivate and Resize
/// operations from the VM's Storage tab.
/// </summary>
public static void ManageVmDisks(string url, string user, string password,
    string sourceVm, string srName, string newVmName = "sdk-example-vm-disks")
{
    const long GiB = 1024L * 1024 * 1024;
    var session = Connect(url, user, password);
    // Not the VM's root/boot disk: a real VM's system disk is unpluggable=false (only a template's
    // non-system disks default to unpluggable), so VBD.unplug on it fails on a real host with
    // VBD_NOT_UNPLUGGABLE - and the VM has to be running in the first place, or unplug fails with
    // VM_BAD_POWER_STATE. Work on a data disk this example adds to its own throwaway VM instead.
    //
    // Plugging and unplugging a disk on a running VM needs the guest's PV drivers
    // (VM_MISSING_PV_DRIVERS otherwise), so the VM is a throwaway copy of sourceVm, a VM with a
    // guest OS and PV drivers.
    var vmRef = CopyOfGuest(session, sourceVm, newVmName);
    VM.start(session, vmRef, false, true);
    WaitForGuestAgent(session, vmRef);

    var srRef = SrByName(session, srName);
    var vdiRef = VDI.create(session, new VDI
    {
        name_label = "sdk-example-data-disk",
        SR = new XenRef<SR>(srRef),
        virtual_size = 4 * GiB,
        type = vdi_type.user,
        sharable = false,
        read_only = false,
        other_config = new Dictionary<string, string>(),
    }).opaque_ref;
    var vbdRef = VBD.create(session, new VBD
    {
        VM = new XenRef<VM>(vmRef),
        VDI = new XenRef<VDI>(vdiRef),
        userdevice = VM.get_allowed_VBD_devices(session, vmRef)[0],
        bootable = false,
        mode = vbd_mode.RW,
        type = vbd_type.Disk,
        empty = false,
        other_config = new Dictionary<string, string>(),
        qos_algorithm_type = "",
        qos_algorithm_params = new Dictionary<string, string>(),
    }).opaque_ref;
    VBD.plug(session, vbdRef);
    Console.WriteLine($"Disk attached:  {VBD.get_currently_attached(session, vbdRef)}");

    // Deactivate = VBD.unplug. The disk stays with the VM; it is just no longer live.
    VBD.unplug(session, vbdRef);
    Console.WriteLine($"After unplug:   {VBD.get_currently_attached(session, vbdRef)}");

    var size = VDI.get_virtual_size(session, vdiRef);
    VDI.resize(session, vdiRef, size * 2);
    Console.WriteLine($"Resized:        {size} -> {VDI.get_virtual_size(session, vdiRef)} bytes");

    VBD.plug(session, vbdRef);
    Console.WriteLine($"After plug:     {VBD.get_currently_attached(session, vbdRef)}");

    // Growing a disk that is attached and live is a DIFFERENT call, not a flag on the same one:
    // resize_online tells the storage layer the guest is using the disk while it grows. Only some
    // storage drivers can (none of a stock XenServer 9's do), and the rest refuse with
    // SR_OPERATION_NOT_SUPPORTED - so ask the SR's driver (its SM record's features) first.
    var srType = SR.get_type(session, srRef);
    var features = SM.get_all_records(session).Values
        .FirstOrDefault(r => r.type == srType)?.features ?? new Dictionary<string, long>();
    if (features.ContainsKey("VDI_RESIZE_ONLINE"))
    {
        var grown = VDI.get_virtual_size(session, vdiRef) + GiB;
        VDI.resize_online(session, vdiRef, grown);
        Console.WriteLine($"Grown online:   {VDI.get_virtual_size(session, vdiRef)} bytes");
    }
    else
    {
        Console.WriteLine($"Grown online:   not supported by {srType} storage; unplug, resize, plug as above");
    }

    VM.hard_shutdown(session, vmRef);
    DestroyVmAndDisks(session, vmRef);
    Console.WriteLine("OK: manage-vm-disks");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Disk attached:  True
After unplug:   False
Resized:        4294967296 -> 8589934592 bytes
After plug:     True
Grown online:   not supported by nfs storage; unplug, resize, plug as above
OK: manage-vm-disks
```

</details>

## Go

Source: [`go/manage_vm_disks.go`](../../go/manage_vm_disks.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// manageVMDisks - Manage VM disks.
//
// Deactivate a running VM's disk, resize it, reactivate it — the Activate/Deactivate and Resize
// operations from the VM's Storage tab.
//
// A real VM's root/boot disk is unpluggable=false (only non-system disks from VM.Provision default
// to unpluggable), and the VM has to be Running for VBD.Unplug to be legal at all
// (VM_BAD_POWER_STATE otherwise on a halted VM). So this works on a NEW data disk added to a
// throwaway VM of its own. No shrink demonstration: real SR backends refuse one outright
// (SR_BACKEND_FAILURE_79).
//
// Plugging and unplugging a disk on a running VM needs the guest's PV drivers
// (VM_MISSING_PV_DRIVERS otherwise), so the VM is a throwaway copy of sourceVM, a VM with a guest OS
// and PV drivers.
func manageVMDisks(url, user, password, sourceVM, srName, newVMName string) {
	const GiB = 1024 * 1024 * 1024
	session := connect(url, user, password)
	vmRef := copyOfGuest(session, sourceVM, newVMName)
	check(xenapi.VM.Start(session, vmRef, false, true))
	waitForGuestAgent(session, vmRef)

	srRef := srByName(session, srName, false)
	vdiRef, err := xenapi.VDI.Create(session, xenapi.VDIRecord{
		NameLabel:   "sdk-example-data-disk",
		SR:          srRef,
		VirtualSize: 4 * GiB,
		Type:        xenapi.VdiTypeUser,
		Sharable:    false,
		ReadOnly:    false,
		OtherConfig: map[string]string{},
	})
	check(err)
	devices, err := xenapi.VM.GetAllowedVBDDevices(session, vmRef)
	check(err)
	vbdRef, err := xenapi.VBD.Create(session, xenapi.VBDRecord{
		VM: vmRef, VDI: vdiRef, Userdevice: devices[0],
		Bootable: false,
		Mode:     xenapi.VbdModeRW, Type: xenapi.VbdTypeDisk, Empty: false,
		// A Go record sends every field, so say so explicitly: a VBD created with unpluggable=false
		// can't be hot-unplugged (VBD_NOT_UNPLUGGABLE). xapi's own default, when the field is left
		// out, is true.
		Unpluggable: true,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
	})
	check(err)
	check(xenapi.VBD.Plug(session, vbdRef))
	attached, _ := xenapi.VBD.GetCurrentlyAttached(session, vbdRef)
	fmt.Printf("Disk attached:  %t\n", attached)

	// Deactivate = VBD.unplug. The disk stays with the VM; it is just no longer live.
	check(xenapi.VBD.Unplug(session, vbdRef))
	attached, _ = xenapi.VBD.GetCurrentlyAttached(session, vbdRef)
	fmt.Printf("After unplug:   %t\n", attached)

	size, err := xenapi.VDI.GetVirtualSize(session, vdiRef)
	check(err)
	check(xenapi.VDI.Resize(session, vdiRef, size*2))
	grown, _ := xenapi.VDI.GetVirtualSize(session, vdiRef)
	fmt.Printf("Resized:        %d -> %d bytes\n", size, grown)

	check(xenapi.VBD.Plug(session, vbdRef))
	attached, _ = xenapi.VBD.GetCurrentlyAttached(session, vbdRef)
	fmt.Printf("After plug:     %t\n", attached)

	// Growing a disk that is attached and live is a DIFFERENT call, not a flag on the same one:
	// ResizeOnline tells the storage layer the guest is using the disk while it grows. Only some
	// storage drivers can (none of a stock XenServer 9's do), and the rest refuse with
	// SR_OPERATION_NOT_SUPPORTED - so ask the SR's driver (its SM record's features) first.
	srType, err := xenapi.SR.GetType(session, srRef)
	check(err)
	sms, err := xenapi.SM.GetAllRecords(session)
	check(err)
	resizeOnline := false
	for _, sm := range sms {
		if sm.Type == srType {
			_, resizeOnline = sm.Features["VDI_RESIZE_ONLINE"]
			break
		}
	}
	if resizeOnline {
		grownOnline := grown + GiB
		check(xenapi.VDI.ResizeOnline(session, vdiRef, grownOnline))
		final, _ := xenapi.VDI.GetVirtualSize(session, vdiRef)
		fmt.Printf("Grown online:   %d bytes\n", final)
	} else {
		fmt.Printf("Grown online:   not supported by %s storage; unplug, resize, plug as above\n", srType)
	}

	check(xenapi.VM.HardShutdown(session, vmRef))
	destroyVMAndDisks(session, vmRef)
	fmt.Println("OK: manage-vm-disks")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Disk attached:  true
After unplug:   false
Resized:        4294967296 -> 8589934592 bytes
After plug:     true
Grown online:   not supported by nfs storage; unplug, resize, plug as above
OK: manage-vm-disks
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/ManageVmDisks.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/ManageVmDisks.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SM;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.HashMap;
import java.util.Map;

import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVmDisks {
    private ManageVmDisks() {
    }

    /**
     * Manage VM disks.
     *
     * <p>Deactivate a running VM's disk, resize it, reactivate it — the Activate/Deactivate and Resize
     * operations from the VM's Storage tab.
     *
     * <p>Not the VM's root/boot disk: a real VM's system disk is unpluggable=false (only a template's
     * non-system disks default to unpluggable), so VBD.unplug on it fails on a real host with
     * VBD_NOT_UNPLUGGABLE - and the VM has to be running in the first place, or unplug fails with
     * VM_BAD_POWER_STATE. Work on a data disk this example adds to its own throwaway VM instead, and
     * tidy up afterwards so the example is repeatable. No shrink: real SR backends refuse one
     * outright (SR_BACKEND_FAILURE_79), so this only ever grows.
     *
     * <p>Plugging and unplugging a disk on a running VM needs the guest's PV drivers
     * (VM_MISSING_PV_DRIVERS otherwise), so the VM is a throwaway copy of sourceVm, a VM with a guest OS
     * and PV drivers.
     */
    public static void run(String url, String user, String password,
            String sourceVm, String srName, String newVmName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        VM vm = copyOfGuest(conn, sourceVm, newVmName);
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);

        SR sr = srByName(conn, srName, false);
        VDI.Record vdiRec = new VDI.Record();
        vdiRec.nameLabel = "sdk-example-data-disk";
        vdiRec.SR = sr;
        vdiRec.virtualSize = 4 * GiB;
        vdiRec.type = Types.VdiType.USER;
        vdiRec.sharable = false;
        vdiRec.readOnly = false;
        vdiRec.otherConfig = new HashMap<>();
        VDI vdi = VDI.create(conn, vdiRec);

        VBD.Record vbdRec = new VBD.Record();
        vbdRec.VM = vm;
        vbdRec.VDI = vdi;
        vbdRec.userdevice = vm.getAllowedVBDDevices(conn).iterator().next();
        vbdRec.bootable = false;
        vbdRec.mode = Types.VbdMode.RW;
        vbdRec.type = Types.VbdType.DISK;
        vbdRec.empty = false;
        // A Java record sends every field, so say so explicitly: a VBD created with unpluggable=false
        // can't be hot-unplugged (VBD_NOT_UNPLUGGABLE). xapi's own default, when the field is left
        // out, is true.
        vbdRec.unpluggable = true;
        vbdRec.otherConfig = new HashMap<>();
        vbdRec.qosAlgorithmType = "";
        vbdRec.qosAlgorithmParams = new HashMap<>();
        VBD vbd = VBD.create(conn, vbdRec);
        vbd.plug(conn);
        System.out.println("Disk attached:  " + vbd.getCurrentlyAttached(conn));

        // Deactivate = VBD.unplug. The disk stays with the VM; it is just no longer live.
        vbd.unplug(conn);
        System.out.println("After unplug:   " + vbd.getCurrentlyAttached(conn));

        Long size = vdi.getVirtualSize(conn);
        vdi.resize(conn, size * 2);
        System.out.println("Resized:        " + size + " -> " + vdi.getVirtualSize(conn) + " bytes");

        vbd.plug(conn);
        System.out.println("After plug:     " + vbd.getCurrentlyAttached(conn));

        // Growing a disk that is attached and live is a DIFFERENT call, not a flag on the same one:
        // resizeOnline tells the storage layer the guest is using the disk while it grows. Only some
        // storage drivers can (none of a stock XenServer 9's do), and the rest refuse with
        // SR_OPERATION_NOT_SUPPORTED - so ask the SR's driver (its SM record's features) first.
        String srType = sr.getType(conn);
        Map<String, Long> features = new HashMap<>();
        for (SM.Record r : SM.getAllRecords(conn).values()) {
            if (srType.equals(r.type)) { features = r.features; break; }
        }
        if (features.containsKey("VDI_RESIZE_ONLINE")) {
            long grown = vdi.getVirtualSize(conn) + GiB;
            vdi.resizeOnline(conn, grown);
            System.out.println("Grown online:   " + vdi.getVirtualSize(conn) + " bytes");
        } else {
            System.out.println("Grown online:   not supported by " + srType
                    + " storage; unplug, resize, plug as above");
        }

        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: manage-vm-disks");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Disk attached:  true
After unplug:   false
Resized:        4294967296 -> 8589934592 bytes
After plug:     true
Grown online:   not supported by nfs storage; unplug, resize, plug as above
OK: manage-vm-disks
```

</details>
