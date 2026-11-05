<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage a VM's CD drive

Add a DVD drive to a VM, insert an ISO from the library and eject it again.

Workflow `manage-vm-media`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/VirtualMachines/ManageVmMedia.cs`](../../csharp/VirtualMachines/ManageVmMedia.cs)

```csharp
/// <summary>
/// Add a DVD drive to a VM, insert an ISO from the library and eject it again.
/// </summary>
/// <example>
/// <code>
/// Workflows.ManageVmMedia("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ManageVmMedia(string url, string user, string password)
{
    var session = Connect(url, user, password);

    var vm = VM.get_all_records(session).First(kv =>
        !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot &&
        kv.Value.power_state == vm_power_state.Halted);
    Console.WriteLine($"Adding a DVD drive to {vm.Value.name_label}");

    // A CD drive is a VBD like any other, distinguished by type=CD; the media is whichever VDI it
    // points at, and an empty drive points at none.
    var device = VM.get_allowed_VBD_devices(session, vm.Key.opaque_ref)[0];
    var drive = VBD.create(session, new VBD
    {
        VM = vm.Key,
        VDI = new XenRef<VDI>(Helper.NullOpaqueRef),
        userdevice = device,
        bootable = false,
        mode = vbd_mode.RO,
        type = vbd_type.CD,
        empty = true,
        unpluggable = true,
        other_config = new Dictionary<string, string>(),
        qos_algorithm_type = "",
        qos_algorithm_params = new Dictionary<string, string>(),
    }).opaque_ref;
    Console.WriteLine($"  drive {device} is empty: {VBD.get_empty(session, drive)}");

    // The ISO library is an SR of content type "iso"; its VDIs are the available images.
    var isoSr = SR.get_all_records(session)
        .First(kv => kv.Value.content_type == "iso" && kv.Value.type != "udev");
    var iso = SR.get_VDIs(session, isoSr.Key.opaque_ref)
        .Select(v => v.opaque_ref)
        .OrderBy(v => VDI.get_name_label(session, v))
        .First();
    Console.WriteLine($"  inserting {VDI.get_name_label(session, iso)}");
    VBD.insert(session, drive, iso);
    Console.WriteLine($"  drive now holds {VDI.get_name_label(session, VBD.get_VDI(session, drive).opaque_ref)}"
                      + $" (empty={VBD.get_empty(session, drive)})");

    VBD.eject(session, drive);
    Console.WriteLine($"  after eject, empty={VBD.get_empty(session, drive)}");

    VBD.destroy(session, drive);
    Console.WriteLine("OK: manage-vm-media");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Adding a DVD drive to db-01
  drive 1 is empty: True
  inserting debian-12.5.0-amd64-netinst.iso
  drive now holds debian-12.5.0-amd64-netinst.iso (empty=False)
  after eject, empty=True
OK: manage-vm-media
```

</details>

## Python

Source: [`python/virtual_machines/manage_vm_media.py`](../../python/virtual_machines/manage_vm_media.py)

```python
"""Manage a VM's CD drive.

Add a DVD drive to a VM, insert an ISO from the library and eject it again.

Run it::

    manage_vm_media("https://xenserver", "root", password)
"""

from connection import connect


def manage_vm_media(url, username, password):
    """Give a VM a DVD drive, put an ISO in it, then eject it.

    A CD drive is a VBD like any other, distinguished by type=CD; the media is whichever
    VDI it points at, and an empty drive points at none."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = next(ref for ref, v in x.VM.get_all_records().items()
              if not v["is_a_template"] and not v["is_control_domain"]
              and not v["is_a_snapshot"] and v["power_state"] == "Halted")
    print("Adding a DVD drive to %s" % x.VM.get_name_label(vm))

    device = x.VM.get_allowed_VBD_devices(vm)[0]
    drive = x.VBD.create({
        "VM": vm, "VDI": "OpaqueRef:NULL", "userdevice": device, "bootable": False,
        "mode": "RO", "type": "CD", "empty": True, "unpluggable": True,
        "other_config": {}, "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("  drive %s is empty: %s" % (device, x.VBD.get_empty(drive)))

    # The ISO library is an SR of content type "iso"; its VDIs are the available images.
    iso_sr = next(ref for ref, s in x.SR.get_all_records().items()
                  if s["content_type"] == "iso" and s["type"] != "udev")
    iso = sorted(x.SR.get_VDIs(iso_sr), key=lambda v: x.VDI.get_name_label(v))[0]
    print("  inserting %s" % x.VDI.get_name_label(iso))
    x.VBD.insert(drive, iso)
    print("  drive now holds %s (empty=%s)"
          % (x.VDI.get_name_label(x.VBD.get_VDI(drive)), x.VBD.get_empty(drive)))

    x.VBD.eject(drive)
    print("  after eject, empty=%s" % x.VBD.get_empty(drive))

    x.VBD.destroy(drive)
    print("OK: manage-vm-media")
    session.logout()
```

<details><summary>Example output</summary>

```text
Adding a DVD drive to db-01
  drive 1 is empty: True
  inserting Windows_Server_2022.iso
  drive now holds Windows_Server_2022.iso (empty=False)
  after eject, empty=True
OK: manage-vm-media
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/ManageVmMedia.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/ManageVmMedia.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.HashMap;
import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVmMedia {
    private ManageVmMedia() {
    }

    /**
     * Manage a VM's CD drive.
     *
     * <p>Add a DVD drive to a VM, insert an ISO from the library and eject it again.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageVmMedia.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = null;
            VM.Record record = null;
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record v = e.getValue();
                if (!v.isATemplate && !v.isControlDomain && !v.isASnapshot
                        && v.powerState == Types.VmPowerState.HALTED) {
                    vm = e.getKey(); record = v; break;
                }
            }
            if (vm == null) throw new Exception("no halted VM");
            System.out.println("Adding a DVD drive to " + record.nameLabel);

            // A CD drive is a VBD like any other, distinguished by type=CD; the media is whichever VDI it
            // points at, and an empty drive points at none.
            String device = vm.getAllowedVBDDevices(conn).iterator().next();
            VBD.Record spec = new VBD.Record();
            spec.VM = vm;
            spec.VDI = new VDI("OpaqueRef:NULL");
            spec.userdevice = device;
            spec.bootable = false;
            spec.mode = Types.VbdMode.RO;
            spec.type = Types.VbdType.CD;
            spec.empty = true;
            spec.unpluggable = true;
            spec.otherConfig = new HashMap<String, String>();
            spec.qosAlgorithmType = "";
            spec.qosAlgorithmParams = new HashMap<String, String>();
            VBD drive = VBD.create(conn, spec);
            System.out.println("  drive " + device + " is empty: " + drive.getEmpty(conn));

            // The ISO library is an SR of content type "iso"; its VDIs are the available images.
            SR isoSr = null;
            for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet())
                if ("iso".equals(e.getValue().contentType) && !"udev".equals(e.getValue().type)) {
                    isoSr = e.getKey(); break;
                }
            if (isoSr == null) throw new Exception("no ISO library");
            java.util.List<VDI> images = new java.util.ArrayList<VDI>(isoSr.getVDIs(conn));
            java.util.Map<VDI, String> names = new HashMap<VDI, String>();
            for (VDI image : images) names.put(image, image.getNameLabel(conn));
            images.sort(java.util.Comparator.comparing(names::get));
            VDI iso = images.get(0);
            System.out.println("  inserting " + names.get(iso));
            drive.insert(conn, iso);
            System.out.println("  drive now holds " + drive.getVDI(conn).getNameLabel(conn)
                    + " (empty=" + drive.getEmpty(conn) + ")");

            drive.eject(conn);
            System.out.println("  after eject, empty=" + drive.getEmpty(conn));

            drive.destroy(conn);
            System.out.println("OK: manage-vm-media");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
Adding a DVD drive to db-01
  drive 11 is empty: true
  inserting Windows_Server_2022.iso
  drive now holds Windows_Server_2022.iso (empty=false)
  after eject, empty=true
OK: manage-vm-media
```

</details>

## Go

Source: [`go/manage_vm_media.go`](../../go/manage_vm_media.go)

```go
package main

import (
	"fmt"
	"sort"

	"go/xenapi"
)

// manageVmMedia - Manage a VM's CD drive.
//
// Add a DVD drive to a VM, insert an ISO from the library and eject it again.
func manageVmMedia(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vm xenapi.VMRef
	var record xenapi.VMRecord
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && !v.IsASnapshot &&
			v.PowerState == xenapi.VMPowerStateHalted {
			vm, record = ref, v
			break
		}
	}
	fmt.Printf("Adding a DVD drive to %s\n", record.NameLabel)

	// A CD drive is a VBD like any other, distinguished by type=CD; the media is whichever VDI it points
	// at, and an empty drive points at none.
	devices, err := xenapi.VM.GetAllowedVBDDevices(session, vm)
	check(err)
	drive, err := xenapi.VBD.Create(session, xenapi.VBDRecord{
		VM:                 vm,
		VDI:                "OpaqueRef:NULL",
		Userdevice:         devices[0],
		Bootable:           false,
		Mode:               xenapi.VbdModeRO,
		Type:               xenapi.VbdTypeCD,
		Empty:              true,
		Unpluggable:        true,
		OtherConfig:        map[string]string{},
		QosAlgorithmParams: map[string]string{},
	})
	check(err)
	empty, err := xenapi.VBD.GetEmpty(session, drive)
	check(err)
	fmt.Printf("  drive %s is empty: %t\n", devices[0], empty)

	// The ISO library is an SR of content type "iso"; its VDIs are the available images.
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var isoSr xenapi.SRRef
	for ref, s := range srs {
		if s.ContentType == "iso" && s.Type != "udev" {
			isoSr = ref
			break
		}
	}
	vdis, err := xenapi.SR.GetVDIs(session, isoSr)
	check(err)
	names := map[xenapi.VDIRef]string{}
	for _, v := range vdis {
		name, err := xenapi.VDI.GetNameLabel(session, v)
		check(err)
		names[v] = name
	}
	sort.Slice(vdis, func(i, j int) bool { return names[vdis[i]] < names[vdis[j]] })
	iso := vdis[0]
	fmt.Printf("  inserting %s\n", names[iso])
	check(xenapi.VBD.Insert(session, drive, iso))

	loaded, err := xenapi.VBD.GetVDI(session, drive)
	check(err)
	empty, err = xenapi.VBD.GetEmpty(session, drive)
	check(err)
	fmt.Printf("  drive now holds %s (empty=%t)\n", names[loaded], empty)

	check(xenapi.VBD.Eject(session, drive))
	empty, err = xenapi.VBD.GetEmpty(session, drive)
	check(err)
	fmt.Printf("  after eject, empty=%t\n", empty)

	check(xenapi.VBD.Destroy(session, drive))
	fmt.Println("OK: manage-vm-media")
}
```

<details><summary>Example output</summary>

```text
Adding a DVD drive to db-01
  drive 1 is empty: true
  inserting Windows_Server_2022.iso
  drive now holds Windows_Server_2022.iso (empty=false)
  after eject, empty=true
OK: manage-vm-media
```

</details>

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-ManageVmMedia.ps1`](../../powershell/VirtualMachines/Invoke-ManageVmMedia.ps1)

```powershell
function Invoke-ManageVmMedia {
    <#
    .SYNOPSIS
        Manage a VM's CD drive.
    .DESCRIPTION
        Add a DVD drive to a VM, insert an ISO from the library and eject it again.
    .EXAMPLE
        Invoke-ManageVmMedia -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.power_state -eq 'Halted'
    } | Select-Object -First 1
    Write-Host "Adding a DVD drive to $($vm.name_label)"

    # A CD drive is a VBD like any other, distinguished by Type CD; the media is whichever VDI it points
    # at, and an empty drive points at none.
    $device = @(Get-XenVMProperty -Ref $vm.opaque_ref -XenProperty AllowedVBDDevices)[0]
    $drive = New-XenVBD -VM $vm -Userdevice $device -Bootable $false -Mode RO -Type CD `
        -Empty $true -Unpluggable $true -OtherConfig @{} -QosAlgorithmType '' `
        -QosAlgorithmParams @{} -PassThru
    Write-Host "  drive $device is empty: $((Get-XenVBD -Ref $drive.opaque_ref).empty)"

    # The ISO library is an SR of content type "iso"; its VDIs are the available images.
    $isoSr = Get-XenSR | Where-Object { $_.content_type -eq 'iso' -and $_.type -ne 'udev' } |
        Select-Object -First 1
    $iso = $isoSr.VDIs | ForEach-Object { Get-XenVDI -Ref $_.opaque_ref } |
        Sort-Object name_label | Select-Object -First 1
    Write-Host "  inserting $($iso.name_label)"
    Invoke-XenVBD -Ref $drive.opaque_ref -XenAction Insert -Vdi $iso

    $loaded = Get-XenVBD -Ref $drive.opaque_ref
    Write-Host ("  drive now holds {0} (empty={1})" -f
        (Get-XenVDI -Ref $loaded.VDI.opaque_ref).name_label, $loaded.empty)

    Invoke-XenVBD -Ref $drive.opaque_ref -XenAction Eject
    Write-Host "  after eject, empty=$((Get-XenVBD -Ref $drive.opaque_ref).empty)"

    Remove-XenVBD -Ref $drive.opaque_ref
    Write-Host "OK: manage-vm-media"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Adding a DVD drive to db-01
  drive 1 is empty: True
  inserting debian-12.5.0-amd64-netinst.iso
  drive now holds debian-12.5.0-amd64-netinst.iso (empty=False)
  after eject, empty=True
OK: manage-vm-media
```

</details>

## xe CLI

Source: [`cli/virtual-machines/manage-vm-media.sh`](../../cli/virtual-machines/manage-vm-media.sh)

```bash
# Manage a VM's CD drive.
#
# Add a DVD drive to a VM, insert an ISO from the library and eject it again.
#
# Run it:
#   ./workflows.sh manage-vm-media https://xenserver root "$password"

manage_vm_media() {
    vm=$(nth_csv "$(xe vm-list power-state=halted --minimal)" 1)
    echo "Adding a DVD drive to $(xe vm-param-get uuid=$vm param-name=name-label)"

    # A CD drive is a VBD like any other, distinguished by type=CD; created without a disk it arrives
    # empty, and the media is whichever VDI it is later pointed at.
    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=allowed-VBD-devices)")")
    drive=$(xe vbd-create vm-uuid=$vm device=$device type=CD mode=RO)
    echo "  drive $device is empty: $(xe vbd-param-get uuid=$drive param-name=empty)"

    # The ISO library is an SR of content type "iso"; its VDIs are the available images.
    # type=iso as well as content-type=iso: a host's physical DVD drive is content-type iso too, but it
    # is type udev and holds whatever disc is in the tray rather than a library of images.
    iso_sr=$(nth_csv "$(xe sr-list content-type=iso type=iso --minimal)" 1)
    iso=$(nth_csv "$(xe vdi-list sr-uuid=$iso_sr --minimal)" 1)
    echo "  inserting $(xe vdi-param-get uuid=$iso param-name=name-label)"
    xe vbd-insert uuid=$drive vdi-uuid=$iso
    echo "  drive now holds $(xe vdi-param-get uuid=$(xe vbd-param-get uuid=$drive param-name=vdi-uuid) param-name=name-label) (empty=$(xe vbd-param-get uuid=$drive param-name=empty))"

    xe vbd-eject uuid=$drive
    echo "  after eject, empty=$(xe vbd-param-get uuid=$drive param-name=empty)"

    xe vbd-destroy uuid=$drive
    echo "OK: manage-vm-media"
}
```

<details><summary>Example output</summary>

```text
Adding a DVD drive to db-01
  drive 1 is empty: true
  inserting ubuntu-22.04.4-live-server-amd64.iso
  drive now holds ubuntu-22.04.4-live-server-amd64.iso (empty=false)
  after eject, empty=true
OK: manage-vm-media
```

</details>
