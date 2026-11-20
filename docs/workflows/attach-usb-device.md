<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Attach a USB device to a VM

List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it again.

**Requires:** a USB device plugged into a host, and a license that includes USB pass-through (Premium Edition).

**Caution:** a VM with a USB passed through cannot be snapshotted, suspended, or pool/storage migrated.

Workflow `attach-usb-device`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-AttachUsbDevice.ps1`](../../powershell/VirtualMachines/Invoke-AttachUsbDevice.ps1)

```powershell
function Invoke-AttachUsbDevice {
    <#
    .SYNOPSIS
        Attach a USB device to a VM.
    .DESCRIPTION
        List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it
        again.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = "web-01"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName

    # Pick deterministically (lowest description, then uuid), not whatever order the server happens
    # to list them in, so the example behaves the same way every run.
    $pusb = Get-XenPUSB | Sort-Object description, uuid | Select-Object -First 1
    Write-Host "Device:         $($pusb.description)"

    # Passthrough is off until an administrator releases the device: attaching one that has not been
    # released fails rather than silently doing nothing.
    Set-XenPUSB -PUSB $pusb -PassthroughEnabled $true

    $vusb = New-XenVUSB -VM $vm -USBGroup $pusb.USB_group -PassThru
    Write-Host "Attached:       $(@((Get-XenVM -Name $VmName).VUSBs).Count) device(s)"

    # Destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM it gets
    # plugged in as soon as it's created, so unplug it first.
    if ((Get-XenVUSB -Ref $vusb).currently_attached) {
        Invoke-XenVUSB -Ref $vusb -XenAction Unplug
    }
    Remove-XenVUSB -VUSB $vusb
    Write-Host "Detached:       $(@((Get-XenVM -Name $VmName).VUSBs).Count) device(s)"
    Set-XenPUSB -PUSB $pusb -PassthroughEnabled $false
    Write-Host "OK: attach-usb-device"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Device:         Kingston Technology DataTraveler 3.0
Attached:       1 device(s)
Detached:       0 device(s)
OK: attach-usb-device
```

</details>

## xe CLI

Source: [`cli/virtual-machines/attach-usb-device.sh`](../../cli/virtual-machines/attach-usb-device.sh)

```bash
# Attach a USB device to a VM.
#
# List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it again.
#
# Run it:
#   ./workflows.sh attach-usb-device https://xenserver root "$password"

attach_usb_device() {
    local vm_uuid pusb_uuid group_uuid vusb_uuid p desc key best_key
    vm_uuid=$(remote_xe vm-list name-label=web-01 --minimal)
    # Pick deterministically (lowest description, then uuid), not whatever order the server lists them in.
    pusb_uuid="" best_key=""
    for p in $(each_csv "$(remote_xe pusb-list --minimal)"); do
        # param-get, not --minimal: --minimal escapes any comma in the value ("Ours Technology\, Inc.").
        desc=$(remote_xe pusb-param-get uuid="$p" param-name=description)
        key="$desc"$'\t'"$p"
        if [ -z "$pusb_uuid" ] || [[ "$key" < "$best_key" ]]; then
            best_key=$key; pusb_uuid=$p
        fi
    done
    echo "Device:         $(remote_xe pusb-param-get uuid="$pusb_uuid" param-name=description)"

    # Passthrough is off until an administrator releases the device: attaching one that has not been
    # released fails rather than silently doing nothing.
    remote_xe pusb-param-set uuid="$pusb_uuid" passthrough-enabled=true

    group_uuid=$(remote_xe pusb-list uuid="$pusb_uuid" params=usb-group-uuid --minimal)
    vusb_uuid=$(remote_xe vusb-create vm-uuid="$vm_uuid" usb-group-uuid="$group_uuid")
    echo "Attached:       $(count_csv "$(remote_xe vusb-list vm-uuid="$vm_uuid" --minimal)") device(s)"

    # vusb-destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM it gets
    # plugged in as soon as it's created, so unplug it first.
    if [ "$(remote_xe vusb-param-get uuid="$vusb_uuid" param-name=currently-attached)" = "true" ]; then
        remote_xe vusb-unplug uuid="$vusb_uuid"
    fi
    remote_xe vusb-destroy uuid="$vusb_uuid"
    echo "Detached:       $(count_csv "$(remote_xe vusb-list vm-uuid="$vm_uuid" --minimal)") device(s)"
    remote_xe pusb-param-set uuid="$pusb_uuid" passthrough-enabled=false
    ok attach-usb-device
}
```

<details><summary>Example output</summary>

```text
Device:         Kingston Technology DataTraveler 3.0
Attached:       1 device(s)
Detached:       0 device(s)
OK: attach-usb-device
```

</details>

## Python

Source: [`python/virtual_machines/attach_usb_device.py`](../../python/virtual_machines/attach_usb_device.py)

```python
"""Attach a USB device to a VM.

List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it
again.

Run it::

    attach_usb_device("https://xenserver", "root", password, "web-01")
"""

from connection import connect


def attach_usb_device(url, username, password, vm_name):
    """Enable passthrough on a host USB device, attach it to a VM, then detach it.

    VUSB.destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM
    it gets plugged in as soon as it's created, so unplug it first, the same unplug-before-destroy
    shape SR.forget and VBD/PBD teardown already need elsewhere in this file."""
    session = connect(url, username, password)
    x = session.xenapi
    vm = x.VM.get_by_name_label(vm_name)[0]

    # Pick deterministically (lowest description, then uuid), not whatever order the server happens
    # to list them in, so the example behaves the same way every run.
    pusb_ref, pusb = min(x.PUSB.get_all_records().items(), key=lambda kv: (kv[1]["description"], kv[1]["uuid"]))
    print(f"Device:         {pusb['description']}")

    # Passthrough is off until an administrator enables it on the device: attaching one that has not
    # been released fails rather than silently doing nothing.
    x.PUSB.set_passthrough_enabled(pusb_ref, True)

    vusb = x.VUSB.create(vm, pusb["USB_group"], {})
    print(f"Attached:       {len(x.VM.get_VUSBs(vm))} device(s)")

    if x.VUSB.get_currently_attached(vusb):
        x.VUSB.unplug(vusb)
    x.VUSB.destroy(vusb)
    print(f"Detached:       {len(x.VM.get_VUSBs(vm))} device(s)")
    x.PUSB.set_passthrough_enabled(pusb_ref, False)
    print("OK: attach-usb-device")
    x.session.logout()
```

<details><summary>Example output</summary>

```text
Device:         Kingston Technology DataTraveler 3.0
Attached:       1 device(s)
Detached:       0 device(s)
OK: attach-usb-device
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/AttachUsbDevice.cs`](../../csharp/VirtualMachines/AttachUsbDevice.cs)

```csharp
/// <summary>
/// List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it again.
/// </summary>
/// <example>
/// <code>
/// Workflows.AttachUsbDevice("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void AttachUsbDevice(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);
    var vm = VM.get_by_name_label(session, vmName)[0];

    // Pick deterministically (lowest description, then uuid), not whatever order the server
    // happens to list them in, so the example behaves the same way every run.
    var pusb = PUSB.get_all_records(session)
        .OrderBy(p => p.Value.description).ThenBy(p => p.Value.uuid).First();
    Console.WriteLine($"Device:         {pusb.Value.description}");

    // Passthrough is off until an administrator enables it on the device — a VUSB.create against a
    // device that has not been released fails rather than silently doing nothing.
    PUSB.set_passthrough_enabled(session, pusb.Key, true);

    var vusb = VUSB.create(session, vm, pusb.Value.USB_group, new Dictionary<string, string>());
    Console.WriteLine($"Attached:       {VM.get_VUSBs(session, vm).Count} device(s)");

    // VUSB.destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM
    // it gets plugged in as soon as it's created, so unplug it first.
    if (VUSB.get_currently_attached(session, vusb)) VUSB.unplug(session, vusb);
    VUSB.destroy(session, vusb);
    Console.WriteLine($"Detached:       {VM.get_VUSBs(session, vm).Count} device(s)");
    PUSB.set_passthrough_enabled(session, pusb.Key, false);
    Console.WriteLine("OK: attach-usb-device");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Device:         Kingston Technology DataTraveler 3.0
Attached:       1 device(s)
Detached:       0 device(s)
OK: attach-usb-device
```

</details>

## Go

Source: [`go/attach_usb_device.go`](../../go/attach_usb_device.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// attachUsbDevice - Attach a USB device to a VM.
//
// List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it
// again.
func attachUsbDevice(url, user, password, vmName string) {
	session := connect(url, user, password)
	defer session.Logout()
	vms, err := xenapi.VM.GetByNameLabel(session, vmName)
	check(err)
	vm := vms[0]

	pusbs, err := xenapi.PUSB.GetAllRecords(session)
	check(err)
	// Pick deterministically (lowest description, then uuid), not whatever order map iteration gives.
	var pusbRef xenapi.PUSBRef
	var pusb xenapi.PUSBRecord
	first := true
	for ref, rec := range pusbs {
		if first || rec.Description < pusb.Description ||
			(rec.Description == pusb.Description && rec.UUID < pusb.UUID) {
			pusbRef, pusb = ref, rec
			first = false
		}
	}
	fmt.Printf("Device:         %s\n", pusb.Description)

	// Passthrough is off until an administrator releases the device: attaching one that has not been
	// released fails rather than silently doing nothing.
	check(xenapi.PUSB.SetPassthroughEnabled(session, pusbRef, true))

	vusb, err := xenapi.VUSB.Create(session, vm, pusb.USBGroup, map[string]string{})
	check(err)
	attached, _ := xenapi.VM.GetVUSBs(session, vm)
	fmt.Printf("Attached:       %d device(s)\n", len(attached))

	// VUSB.Destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM
	// it gets plugged in as soon as it's created, so unplug it first.
	vusbRecord, err := xenapi.VUSB.GetRecord(session, vusb)
	check(err)
	if vusbRecord.CurrentlyAttached {
		check(xenapi.VUSB.Unplug(session, vusb))
	}
	check(xenapi.VUSB.Destroy(session, vusb))
	detached, _ := xenapi.VM.GetVUSBs(session, vm)
	fmt.Printf("Detached:       %d device(s)\n", len(detached))
	check(xenapi.PUSB.SetPassthroughEnabled(session, pusbRef, false))
	fmt.Println("OK: attach-usb-device")
}
```

<details><summary>Example output</summary>

```text
Device:         Kingston Technology DataTraveler 3.0
Attached:       1 device(s)
Detached:       0 device(s)
OK: attach-usb-device
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/AttachUsbDevice.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/AttachUsbDevice.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.PUSB;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VUSB;

import java.util.Comparator;
import java.util.HashMap;
import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class AttachUsbDevice {
    private AttachUsbDevice() {
    }

    /**
     * Attach a USB device to a VM.
     *
     * <p>List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it
     * again.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * AttachUsbDevice.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = VM.getByNameLabel(conn, vmName).iterator().next();

            // Pick deterministically (lowest description, then uuid), not whatever order the server
            // happens to list them in, so the example behaves the same way every run.
            Map.Entry<PUSB, PUSB.Record> entry = PUSB.getAllRecords(conn).entrySet().stream()
                    .min(Comparator.<Map.Entry<PUSB, PUSB.Record>, String>comparing(e -> e.getValue().description)
                            .thenComparing(e -> e.getValue().uuid))
                    .orElseThrow();
            System.out.println("Device:         " + entry.getValue().description);

            // Passthrough is off until an administrator releases the device: attaching one that has
            // not been released fails rather than silently doing nothing.
            entry.getKey().setPassthroughEnabled(conn, true);

            VUSB vusb = VUSB.create(conn, vm, entry.getValue().USBGroup,
                    new HashMap<String, String>());
            System.out.println("Attached:       " + vm.getVUSBs(conn).size() + " device(s)");

            // VUSB.destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM
            // it gets plugged in as soon as it's created, so unplug it first.
            if (vusb.getCurrentlyAttached(conn)) vusb.unplug(conn);
            vusb.destroy(conn);
            System.out.println("Detached:       " + vm.getVUSBs(conn).size() + " device(s)");
            entry.getKey().setPassthroughEnabled(conn, false);
            System.out.println("OK: attach-usb-device");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
Device:         Kingston Technology DataTraveler 3.0
Attached:       1 device(s)
Detached:       0 device(s)
OK: attach-usb-device
```

</details>
