<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Attach an existing disk to another VM

Move a disk between VMs by detaching and re-attaching it, without copying the data.

Workflow `attach-existing-disk`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Storage/AttachExistingDisk.cs`](../../csharp/Storage/AttachExistingDisk.cs)

```csharp
/// <summary>
/// Move a disk between VMs by detaching and re-attaching it, without copying the data.
/// </summary>
public static void AttachExistingDisk(string url, string user, string password)
{
    const long GiB = 1024L * 1024 * 1024;
    var session = Connect(url, user, password);

    // A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk between
    // VMs is removing one VBD and creating another — no copying, and the data stays where it is.
    var halted = VM.get_all_records(session)
        .Where(kv => !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot
                     && kv.Value.power_state == vm_power_state.Halted)
        .Select(kv => kv.Key.opaque_ref).ToList();

    var sr = SR.get_all_records(session).First(kv =>
        kv.Value.shared && kv.Value.content_type != "iso"
        && kv.Value.type != "iso" && kv.Value.type != "udev").Key.opaque_ref;
    var vdi = VDI.create(session, new VDI
    {
        name_label = "sdk-example-portable-disk",
        SR = new XenRef<SR>(sr),
        virtual_size = 4 * GiB,
        type = vdi_type.user,
        sharable = false,
        read_only = false,
        other_config = new Dictionary<string, string>(),
    }).opaque_ref;
    Console.WriteLine($"Disk {VDI.get_name_label(session, vdi)} created on "
                      + SR.get_name_label(session, sr));

    var vbd = AttachVdi(session, halted[0], vdi);
    Console.WriteLine($"  attached to {VM.get_name_label(session, halted[0])}");

    // Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
    VBD.destroy(session, vbd);
    Console.WriteLine($"  detached:   the disk still exists ({VDI.get_virtual_size(session, vdi)} bytes)");

    AttachVdi(session, halted[1], vdi);
    Console.WriteLine($"  attached to {VM.get_name_label(session, halted[1])}");
    Console.WriteLine($"  the disk is on {VDI.get_VBDs(session, vdi).Count} VM(s)");

    foreach (var r in VDI.get_VBDs(session, vdi)) VBD.destroy(session, r.opaque_ref);
    VDI.destroy(session, vdi);
    Console.WriteLine("OK: attach-existing-disk");
    session.logout();
}

/// <summary>Join an existing disk to a VM on its next free device slot.</summary>
private static string AttachVdi(Session session, string vm, string vdi) => VBD.create(session, new VBD
{
    VM = new XenRef<VM>(vm),
    VDI = new XenRef<VDI>(vdi),
    userdevice = VM.get_allowed_VBD_devices(session, vm).First(),
    bootable = false,
    mode = vbd_mode.RW,
    type = vbd_type.Disk,
    empty = false,
    other_config = new Dictionary<string, string>(),
    qos_algorithm_type = "",
    qos_algorithm_params = new Dictionary<string, string>(),
}).opaque_ref;
```

<details><summary>Example output</summary>

```text
Disk sdk-example-portable-disk created on Shared NFS
  attached to db-01
  detached:   the disk still exists (4294967296 bytes)
  attached to secure-01
  the disk is on 1 VM(s)
OK: attach-existing-disk
```

</details>

## Python

Source: [`python/storage/attach_existing_disk.py`](../../python/storage/attach_existing_disk.py)

```python
"""Attach an existing disk to another VM.

Move a disk between VMs by detaching and re-attaching it, without copying the data.
"""

from connection import connect


def attach_existing_disk(url, username, password):
    """Move an existing disk from one VM to another by re-attaching it.

    A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk
    between VMs is removing one VBD and creating another -- no copying, and the data stays
    exactly where it is. This is how you recover a disk from a VM you are retiring."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    x = session.xenapi

    halted = [ref for ref, r in x.VM.get_all_records().items()
              if not r["is_a_template"] and not r["is_control_domain"] and not r["is_a_snapshot"]
              and r["power_state"] == "Halted"]
    first, second = halted[0], halted[1]

    sr = next(ref for ref, r in x.SR.get_all_records().items()
              if r["shared"] and r["content_type"] != "iso" and r["type"] not in ("iso", "udev"))
    vdi = x.VDI.create({
        "name_label": "sdk-example-portable-disk",
        "SR": sr, "virtual_size": str(4 * GIB), "type": "user",
        "sharable": False, "read_only": False, "other_config": {},
    })
    print("Disk %s created on %s" % (x.VDI.get_name_label(vdi), x.SR.get_name_label(sr)))

    vbd = attach_vdi(x, first, vdi)
    print("  attached to %s" % x.VM.get_name_label(first))

    # Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
    x.VBD.destroy(vbd)
    print("  detached:   the disk still exists (%d bytes)" % int(x.VDI.get_virtual_size(vdi)))

    attach_vdi(x, second, vdi)
    print("  attached to %s" % x.VM.get_name_label(second))
    print("  the disk is on %d VM(s)" % len(x.VDI.get_VBDs(vdi)))

    for ref in x.VDI.get_VBDs(vdi):
        x.VBD.destroy(ref)
    x.VDI.destroy(vdi)
    print("OK: attach-existing-disk")
    session.logout()


def attach_vdi(x, vm, vdi):
    """Join an existing disk to a VM on its next free device slot."""
    return x.VBD.create({
        "VM": vm, "VDI": vdi, "userdevice": x.VM.get_allowed_VBD_devices(vm)[0],
        "bootable": False,
        "mode": "RW", "type": "Disk", "empty": False, "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
```

<details><summary>Example output</summary>

```text
Disk sdk-example-portable-disk created on Shared NFS
  attached to db-01
  detached:   the disk still exists (4294967296 bytes)
  attached to secure-01
  the disk is on 1 VM(s)
OK: attach-existing-disk
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/AttachExistingDisk.java`](../../java/src/main/java/com/xenserver/samples/storage/AttachExistingDisk.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class AttachExistingDisk {
    private AttachExistingDisk() {
    }

    /**
     * Attach an existing disk to another VM.
     *
     * <p>Move a disk between VMs by detaching and re-attaching it, without copying the data.
     */
    public static void run(String url, String user, String password) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        try {
            // A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk
            // between VMs is removing one VBD and creating another - no copying, and the data stays
            // exactly where it is.
            java.util.List<VM> halted = new java.util.ArrayList<>();
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record r = e.getValue();
                if (!r.isATemplate && !r.isControlDomain && !r.isASnapshot
                        && r.powerState == Types.VmPowerState.HALTED)
                    halted.add(e.getKey());
            }

            SR sr = null;
            for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet()) {
                SR.Record r = e.getValue();
                if (r.shared && !"iso".equals(r.contentType)
                        && r.type != null && !r.type.equals("iso") && !r.type.equals("udev")) {
                    sr = e.getKey(); break;
                }
            }

            VDI.Record vdiRecord = new VDI.Record();
            vdiRecord.nameLabel = "sdk-example-portable-disk";
            vdiRecord.SR = sr;
            vdiRecord.virtualSize = 4 * GiB;
            vdiRecord.type = Types.VdiType.USER;
            vdiRecord.sharable = false;
            vdiRecord.readOnly = false;
            vdiRecord.otherConfig = new java.util.HashMap<>();
            VDI vdi = VDI.create(conn, vdiRecord);
            System.out.printf("Disk %s created on %s%n", vdi.getNameLabel(conn), sr.getNameLabel(conn));

            VBD vbd = attachVdi(conn, halted.get(0), vdi);
            System.out.println("  attached to " + halted.get(0).getNameLabel(conn));

            // Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
            vbd.destroy(conn);
            System.out.printf("  detached:   the disk still exists (%d bytes)%n", vdi.getVirtualSize(conn));

            attachVdi(conn, halted.get(1), vdi);
            System.out.println("  attached to " + halted.get(1).getNameLabel(conn));
            System.out.printf("  the disk is on %d VM(s)%n", vdi.getVBDs(conn).size());

            for (VBD b : vdi.getVBDs(conn)) b.destroy(conn);
            vdi.destroy(conn);
            System.out.println("OK: attach-existing-disk");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Join an existing disk to a VM on its next free device slot.
     */
    private static VBD attachVdi(Connection conn, VM vm, VDI vdi) throws Exception {
        VBD.Record record = new VBD.Record();
        record.VM = vm;
        record.VDI = vdi;
        record.userdevice = vm.getAllowedVBDDevices(conn).iterator().next();
        record.bootable = false;
        record.mode = Types.VbdMode.RW;
        record.type = Types.VbdType.DISK;
        record.empty = false;
        record.otherConfig = new java.util.HashMap<>();
        record.qosAlgorithmType = "";
        record.qosAlgorithmParams = new java.util.HashMap<>();
        return VBD.create(conn, record);
    }
}
```

<details><summary>Example output</summary>

```text
Disk sdk-example-portable-disk created on Shared NFS
  attached to db-01
  detached:   the disk still exists (4294967296 bytes)
  attached to secure-01
  the disk is on 1 VM(s)
OK: attach-existing-disk
```

</details>

## Go

Source: [`go/attach_existing_disk.go`](../../go/attach_existing_disk.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// attachExistingDisk - Attach an existing disk to another VM.
//
// Move a disk between VMs by detaching and re-attaching it, without copying the data.
func attachExistingDisk(url, user, password string) {
	const GiB = 1024 * 1024 * 1024
	session := connect(url, user, password)
	defer session.Logout()

	// A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk between VMs
	// is removing one VBD and creating another - no copying, and the data stays where it is.
	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var halted []xenapi.VMRef
	for ref, r := range vms {
		if !r.IsATemplate && !r.IsControlDomain && !r.IsASnapshot && r.PowerState == xenapi.VMPowerStateHalted {
			halted = append(halted, ref)
		}
	}

	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var sr xenapi.SRRef
	for ref, r := range srs {
		if r.Shared && r.ContentType != "iso" && r.Type != "iso" && r.Type != "udev" {
			sr = ref
			break
		}
	}
	vdi, err := xenapi.VDI.Create(session, xenapi.VDIRecord{
		NameLabel:   "sdk-example-portable-disk",
		SR:          sr,
		VirtualSize: 4 * GiB,
		Type:        xenapi.VdiTypeUser,
		OtherConfig: map[string]string{},
	})
	check(err)
	vdiName, _ := xenapi.VDI.GetNameLabel(session, vdi)
	srName, _ := xenapi.SR.GetNameLabel(session, sr)
	fmt.Printf("Disk %s created on %s\n", vdiName, srName)

	vbd := attachVdi(session, halted[0], vdi)
	firstName, _ := xenapi.VM.GetNameLabel(session, halted[0])
	fmt.Printf("  attached to %s\n", firstName)

	// Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
	check(xenapi.VBD.Destroy(session, vbd))
	size, _ := xenapi.VDI.GetVirtualSize(session, vdi)
	fmt.Printf("  detached:   the disk still exists (%d bytes)\n", size)

	attachVdi(session, halted[1], vdi)
	secondName, _ := xenapi.VM.GetNameLabel(session, halted[1])
	fmt.Printf("  attached to %s\n", secondName)
	vbds, _ := xenapi.VDI.GetVBDs(session, vdi)
	fmt.Printf("  the disk is on %d VM(s)\n", len(vbds))

	for _, ref := range vbds {
		check(xenapi.VBD.Destroy(session, ref))
	}
	check(xenapi.VDI.Destroy(session, vdi))
	fmt.Println("OK: attach-existing-disk")
}

// attachVdi joins an existing disk to a VM on its next free device slot.
func attachVdi(session *xenapi.Session, vm xenapi.VMRef, vdi xenapi.VDIRef) xenapi.VBDRef {
	devices, err := xenapi.VM.GetAllowedVBDDevices(session, vm)
	check(err)
	vbd, err := xenapi.VBD.Create(session, xenapi.VBDRecord{
		VM: vm, VDI: vdi, Userdevice: devices[0],
		Bootable: false,
		Mode:     xenapi.VbdModeRW, Type: xenapi.VbdTypeDisk, Empty: false,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
	})
	check(err)
	return vbd
}
```

<details><summary>Example output</summary>

```text
Disk sdk-example-portable-disk created on Shared NFS
  attached to secure-01
  detached:   the disk still exists (4294967296 bytes)
  attached to db-01
  the disk is on 1 VM(s)
OK: attach-existing-disk
```

</details>

## PowerShell

Source: [`powershell/Storage/Invoke-AttachExistingDisk.ps1`](../../powershell/Storage/Invoke-AttachExistingDisk.ps1)

```powershell
function Invoke-AttachExistingDisk {
    <#
    .SYNOPSIS
        Attach an existing disk to another VM.
    .DESCRIPTION
        Move a disk between VMs by detaching and re-attaching it, without copying the data.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk between VMs
    # is removing one VBD and creating another - no copying, and the data stays exactly where it is.
    $halted = @(Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.power_state -eq 'Halted'
    })
    $sr = Get-XenSR | Where-Object {
        $_.shared -and $_.content_type -ne 'iso' -and $_.type -notin @('iso', 'udev')
    } | Select-Object -First 1

    $vdi = New-XenVDI -SR $sr -NameLabel 'sdk-example-portable-disk' -VirtualSize 4GB `
        -Type User -Sharable $false -ReadOnly $false -PassThru
    Write-Host "Disk $($vdi.name_label) created on $($sr.name_label)"

    $vbd = Add-ExampleDisk -VM $halted[0] -Vdi $vdi
    Write-Host "  attached to $($halted[0].name_label)"

    # Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
    Remove-XenVBD -Ref $vbd.opaque_ref
    Write-Host "  detached:   the disk still exists ($((Get-XenVDI -Ref $vdi.opaque_ref).virtual_size) bytes)"

    Add-ExampleDisk -VM $halted[1] -Vdi $vdi | Out-Null
    Write-Host "  attached to $($halted[1].name_label)"
    $vbds = @((Get-XenVDI -Ref $vdi.opaque_ref).VBDs)
    Write-Host "  the disk is on $($vbds.Count) VM(s)"

    foreach ($b in $vbds) { Remove-XenVBD -Ref $b.opaque_ref }
    Remove-XenVDI -Ref $vdi.opaque_ref
    Write-Host "OK: attach-existing-disk"
    $session | Disconnect-XenServer
}

function Add-ExampleDisk {
    <#
    .SYNOPSIS
        Join an existing disk to a VM on its next free device slot.
    #>
    param($VM, $Vdi)
    New-XenVBD -VM $VM -VDI $Vdi -Userdevice (Get-XenVMProperty -Ref $VM.opaque_ref -XenProperty AllowedVBDDevices)[0] `
        -Mode RW -Type Disk -Bootable $false -Empty $false -PassThru
}
```

<details><summary>Example output</summary>

```text
Disk sdk-example-portable-disk created on Shared NFS
  attached to db-01
  detached:   the disk still exists (4294967296 bytes)
  attached to secure-01
  the disk is on 1 VM(s)
OK: attach-existing-disk
```

</details>

## xe CLI

Source: [`cli/storage/attach-existing-disk.sh`](../../cli/storage/attach-existing-disk.sh)

```bash
# Attach an existing disk to another VM.
#
# Move a disk between VMs by detaching and re-attaching it, without copying the data.
#
# Run it:
#   ./workflows.sh attach-existing-disk https://xenserver root "$password"

attach_existing_disk() {
    # A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk between VMs
    # is removing one VBD and creating another - no copying, and the data stays exactly where it is.
    halted=$(xe vm-list power-state=halted --minimal)
    first=$(nth_csv "$halted" 1)
    second=$(nth_csv "$halted" 2)
    sr=$(default_sr)

    vdi=$(xe vdi-create sr-uuid=$sr name-label=xe-example-portable-disk virtual-size=4294967296 type=user)
    echo "Disk $(xe vdi-param-get uuid=$vdi param-name=name-label) created on $(xe sr-param-get uuid=$sr param-name=name-label)"

    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$first param-name=allowed-VBD-devices)")")
    vbd=$(xe vbd-create vm-uuid=$first vdi-uuid=$vdi device=$device type=Disk mode=RW)
    echo "  attached to $(xe vm-param-get uuid=$first param-name=name-label)"

    # Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
    xe vbd-destroy uuid=$vbd
    echo "  detached:   the disk still exists ($(xe vdi-param-get uuid=$vdi param-name=virtual-size) bytes)"

    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$second param-name=allowed-VBD-devices)")")
    vbd2=$(xe vbd-create vm-uuid=$second vdi-uuid=$vdi device=$device type=Disk mode=RW)
    echo "  attached to $(xe vm-param-get uuid=$second param-name=name-label)"
    echo "  the disk is on $(count_csv "$(set_to_csv "$(xe vdi-param-get uuid=$vdi param-name=vbds)")") VM(s)"

    xe vbd-destroy uuid=$vbd2
    xe vdi-destroy uuid=$vdi
    echo "OK: attach-existing-disk"
}
```

<details><summary>Example output</summary>

```text
Disk xe-example-portable-disk created on Shared NFS
  attached to db-01
  detached:   the disk still exists (4294967296 bytes)
  attached to secure-01
  the disk is on 0 VM(s)
OK: attach-existing-disk
```

</details>
