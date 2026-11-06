<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create a VM (full workflow)

Create a VM end to end: pick a template, name the VM, choose an installation source and a home server, set CPU & memory, add a disk on a storage repository, attach a network interface and start it — the full sequence, rather than a single clone call.

Workflow `new-vm-wizard`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-NewVmWizard.ps1`](../../powershell/VirtualMachines/Invoke-NewVmWizard.ps1)

```powershell
function Invoke-NewVmWizard {
    <#
    .SYNOPSIS
        Create a VM (full workflow).
    .DESCRIPTION
        Create a VM end to end: pick a template, name the VM, choose an installation source and a home
        server, set CPU & memory, add a disk on a storage repository, attach a network interface and start
        it — the full sequence, rather than a single clone call.
    .EXAMPLE
        Invoke-NewVmWizard -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "wizard-vm"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Page 1 - Template.
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    Write-Host "Template:      $($template.name_label)"

    # Page 2 - Name and description.
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    $ref = $vm.opaque_ref
    $vm | Set-XenVM -NameDescription "Created by the full New VM wizard example"
    $vm | Set-XenVM -IsATemplate $false
    Write-Host "Created VM:    $((Get-XenVM -Ref $ref).uuid)"

    # Page 3 - Installation media (a network install repository). Set replaces other_config wholesale,
    # so merge our key into a copy of the current map.
    $current = (Get-XenVM -Ref $ref).other_config
    $oc = @{}
    foreach ($k in $current.Keys) { $oc[$k] = $current[$k] }
    $oc["install-repository"] = "http://mirror.example.com/rocky/9/os/x86_64"
    $vm | Set-XenVM -OtherConfig $oc
    Write-Host "Install media: network repository"

    # Page 4 - Home server (affinity).
    $xenHost = Get-XenHost | Select-Object -First 1
    $vm | Set-XenVM -Affinity $xenHost
    Write-Host "Home server:   $($xenHost.name_label)"

    # Page 5 - CPU & Memory. -MemoryLimits takes [static_min, static_max, dynamic_min, dynamic_max].
    $vm | Set-XenVM -VCPUsMax 2 -VCPUsAtStartup 2
    $vm | Set-XenVM -MemoryLimits (512MB, 2GB, 2GB, 2GB)
    Write-Host "CPU/memory:    2 vCPUs, 2 GiB"

    # Page 6 - Storage: add a disk on a (non-ISO) SR.
    $sr = Get-XenSR | Where-Object { $_.content_type -ne 'iso' -and $_.type -notin @('iso', 'udev') } | Select-Object -First 1
    $vbdDevice = (Get-XenVMProperty -Ref $ref -XenProperty AllowedVBDDevices)[0]
    $vdi = New-XenVDI -NameLabel "$NewVmName disk 0" -NameDescription "System disk created by the wizard example" `
        -SR $sr -VirtualSize 24GB -Type system -Sharable $false -ReadOnly $false -PassThru
    New-XenVBD -VM (Get-XenVM -Ref $ref) -VDI $vdi -Userdevice $vbdDevice -Bootable $true `
        -Mode RW -Type Disk -Empty $false | Out-Null
    Write-Host "Storage:       24 GiB disk on $($sr.name_label)"

    # Page 7 - Networking: attach a VIF to a network.
    $net = Get-XenNetwork | Select-Object -First 1
    $vifDevice = (Get-XenVMProperty -Ref $ref -XenProperty AllowedVIFDevices)[0]
    New-XenVIF -VM (Get-XenVM -Ref $ref) -Network $net -Device $vifDevice -MAC "" -MTU 1500 | Out-Null
    Write-Host "Networking:    NIC on $($net.name_label)"

    # Page 8 - Finish: start the VM.
    $vm | Invoke-XenVM -XenAction Start

    $started = Get-XenVM -Ref $ref
    Write-Host "--- Result ---"
    Write-Host "power state:   $($started.power_state)"
    Write-Host "vCPUs:         $($started.VCPUs_max)"
    Write-Host "disks:         $(@($started.VBDs).Count), NICs: $(@($started.VIFs).Count)"

    # Tidy up so the example is repeatable.
    $vm | Invoke-XenVM -XenAction HardShutdown
    $vm | Remove-XenVM
    $vdi | Remove-XenVDI
    Write-Host "OK: new-vm-wizard"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Template:      Rocky Linux 8
Created VM:    00000001-0000-0000-f509-000000000000
Install media: network repository
Home server:   sdk-host1
CPU/memory:    2 vCPUs, 2 GiB
Storage:       24 GiB disk on Shared NFS
Networking:    NIC on Pool-wide network associated with eth0
--- Result ---
power state:   Running
vCPUs:         2
disks:         1, NICs: 1
OK: new-vm-wizard
```

</details>

## xe CLI

Source: [`cli/virtual-machines/new-vm-wizard.sh`](../../cli/virtual-machines/new-vm-wizard.sh)

```bash
# Create a VM (full workflow).
#
# Create a VM end to end: pick a template, name the VM, choose an installation source and a home server, set
# CPU & memory, add a disk on a storage repository, attach a network interface and start it — the full
# sequence, rather than a single clone call.
#
# Run it:
#   ./workflows.sh new-vm-wizard https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

new_vm_wizard() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-wizard-vm)
    xe vm-param-set uuid=$vm VCPUs-max=2 VCPUs-at-startup=2
    xe vm-memory-limits-set uuid=$vm static-min=512MiB static-max=2GiB dynamic-min=2GiB dynamic-max=2GiB
    vdi=$(xe vdi-create sr-uuid=$(default_sr) name-label="xe-wizard disk" virtual-size=24GiB type=user)
    xe vbd-create vm-uuid=$vm vdi-uuid=$vdi device=1 type=Disk mode=RW >/dev/null
    xe vif-create vm-uuid=$vm network-uuid=$(first_csv "$(xe network-list --minimal)") device=0 >/dev/null
    xe vm-start uuid=$vm
    echo "power-state: $(xe vm-param-get uuid=$vm param-name=power-state)"
    echo "vCPUs:       $(xe vm-param-get uuid=$vm param-name=VCPUs-max)"
    # Tidy up so the example is repeatable: stop the VM, then vm-uninstall destroys it and the disks it
    # owns (vm-destroy would leave the disks behind). It owns only the template's disks - vm-install marks
    # those (VBD other-config:owner) - not one added with a plain vbd-create, so destroy that one too.
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    xe vdi-destroy uuid=$vdi
    echo "OK: new-vm-wizard"
}
```

<details><summary>Example output</summary>

```text
power-state: running
vCPUs:       2
OK: new-vm-wizard
```

</details>

## Python

Source: [`python/virtual_machines/new_vm_wizard.py`](../../python/virtual_machines/new_vm_wizard.py)

```python
"""Create a VM (full workflow).

Create a VM end to end: pick a template, name the VM, choose an installation source and a home
server, set CPU & memory, add a disk on a storage repository, attach a network interface and start
it — the full sequence, rather than a single clone call.

Run it::

    new_vm_wizard("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import template_by_name


def new_vm_wizard(url, username, password, template_name, new_vm_name="wizard-vm"):
    """
    Create a VM the way a New VM wizard does, end to end: start from the named template, name the VM,
    choose an installation source, a home server, CPU & memory, add a disk, attach a network,
    then start it.
    """
    GIB = 1024 * 1024 * 1024
    MIB = 1024 * 1024

    session = connect(url, username, password)
    # Page 1 - Template.
    template_ref = template_by_name(session, template_name)
    print("Template:      %s" % session.xenapi.VM.get_name_label(template_ref))

    # Page 2 - Name and description.
    vm = session.xenapi.VM.clone(template_ref, new_vm_name)
    session.xenapi.VM.set_name_description(vm, "Created by the full New VM wizard example")
    session.xenapi.VM.set_is_a_template(vm, False)
    print("Created VM:    %s" % session.xenapi.VM.get_uuid(vm))

    # Page 3 - Installation media (a network install repository).
    session.xenapi.VM.add_to_other_config(vm, "install-repository",
                                          "http://mirror.example.com/rocky/9/os/x86_64")
    print("Install media: network repository")

    # Page 4 - Home server (affinity).
    host_ref, host = next(iter(session.xenapi.host.get_all_records().items()))
    session.xenapi.VM.set_affinity(vm, host_ref)
    print("Home server:   %s" % host["name_label"])

    # Page 5 - CPU & Memory (memory sizes are passed as strings: they exceed XML-RPC's 32-bit int).
    session.xenapi.VM.set_VCPUs_max(vm, "2")
    session.xenapi.VM.set_VCPUs_at_startup(vm, "2")
    session.xenapi.VM.set_memory_limits(vm, str(512 * MIB), str(2 * GIB), str(2 * GIB), str(2 * GIB))
    print("CPU/memory:    2 vCPUs, 2 GiB")

    # Page 6 - Storage: add a disk on a (non-ISO) SR.
    sr_ref = next(ref for ref, r in session.xenapi.SR.get_all_records().items()
                  if r["content_type"] != "iso" and r["type"] not in ("iso", "udev"))
    vbd_device = session.xenapi.VM.get_allowed_VBD_devices(vm)[0]
    vdi = session.xenapi.VDI.create({
        "name_label": "%s disk 0" % new_vm_name,
        "name_description": "System disk created by the wizard example",
        "SR": sr_ref,
        "virtual_size": str(24 * GIB),
        "type": "system",
        "sharable": False,
        "read_only": False,
        "other_config": {},
    })
    session.xenapi.VBD.create({
        "VM": vm, "VDI": vdi, "userdevice": vbd_device, "bootable": True,
        "mode": "RW", "type": "Disk", "empty": False, "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("Storage:       24 GiB disk on %s" % session.xenapi.SR.get_name_label(sr_ref))

    # Page 7 - Networking: attach a VIF to a network.
    net_ref, net = next(iter(session.xenapi.network.get_all_records().items()))
    vif_device = session.xenapi.VM.get_allowed_VIF_devices(vm)[0]
    session.xenapi.VIF.create({
        "VM": vm, "network": net_ref, "device": vif_device, "MAC": "",
        "MTU": "1500", "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("Networking:    NIC on %s" % net["name_label"])

    # Page 8 - Finish: start the VM.
    session.xenapi.VM.start(vm, False, True)

    # Report the assembled VM.
    print("--- Result ---")
    print("power state:   %s" % session.xenapi.VM.get_power_state(vm))
    print("vCPUs:         %s" % session.xenapi.VM.get_VCPUs_max(vm))
    print("disks:         %d, NICs: %d" %
          (len(session.xenapi.VM.get_VBDs(vm)), len(session.xenapi.VM.get_VIFs(vm))))

    # Tidy up so the example is repeatable.
    session.xenapi.VM.hard_shutdown(vm)
    session.xenapi.VM.destroy(vm)
    session.xenapi.VDI.destroy(vdi)
    print("Cleaned up the example VM.")

    print("OK: new-vm-wizard")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Template:      Rocky Linux 8
Created VM:    00000001-0000-0000-f509-000000000000
Install media: network repository
Home server:   sdk-host1
CPU/memory:    2 vCPUs, 2 GiB
Storage:       24 GiB disk on Shared NFS
Networking:    NIC on Pool-wide network associated with eth0
--- Result ---
power state:   Running
vCPUs:         2
disks:         1, NICs: 1
Cleaned up the example VM.
OK: new-vm-wizard
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/NewVmWizard.cs`](../../csharp/VirtualMachines/NewVmWizard.cs)

```csharp
/// <summary>
/// Create a VM end to end: pick a template, name the VM, choose an installation source and a home server,
/// set CPU &amp; memory, add a disk on a storage repository, attach a network interface and start it —
/// the full sequence, rather than a single clone call.
/// </summary>
/// <example>
/// <code>
/// Workflows.NewVmWizard("https://xenserver", "root", password, "Rocky Linux 8");
/// </code>
/// </example>
public static void NewVmWizard(string url, string user, string password,
    string templateName, string newVmName = "wizard-vm")
{
    const long GiB = 1024L * 1024 * 1024, MiB = 1024L * 1024;

    var session = Connect(url, user, password);
    // Page 1 - Template.
    var templateRef = TemplateByName(session, templateName);
    Console.WriteLine($"Template:      {VM.get_name_label(session, templateRef)}");

    // Page 2 - Name and description.
    var vm = VM.clone(session, templateRef, newVmName).opaque_ref;
    VM.set_name_description(session, vm, "Created by the full New VM wizard example");
    VM.set_is_a_template(session, vm, false);
    Console.WriteLine($"Created VM:    {VM.get_uuid(session, vm)}");

    // Page 3 - Installation media (a network install repository).
    VM.add_to_other_config(session, vm, "install-repository", "http://mirror.example.com/rocky/9/os/x86_64");
    Console.WriteLine("Install media: network repository");

    // Page 4 - Home server (affinity).
    var (hostRef, host) = Host.get_all_records(session).First();
    VM.set_affinity(session, vm, hostRef.opaque_ref);
    Console.WriteLine($"Home server:   {host.name_label}");

    // Page 5 - CPU & Memory.
    VM.set_VCPUs_max(session, vm, 2);
    VM.set_VCPUs_at_startup(session, vm, 2);
    VM.set_memory_limits(session, vm, 512 * MiB, 2 * GiB, 2 * GiB, 2 * GiB);
    Console.WriteLine("CPU/memory:    2 vCPUs, 2 GiB");

    // Page 6 - Storage: add a disk on a (non-ISO) SR.
    var (srRef, sr) = SR.get_all_records(session)
        .First(kv => kv.Value.content_type != "iso" && kv.Value.type != "iso" && kv.Value.type != "udev");
    var vbdDevice = VM.get_allowed_VBD_devices(session, vm)[0];
    var vdi = VDI.create(session, new VDI
    {
        name_label = $"{newVmName} disk 0",
        name_description = "System disk created by the wizard example",
        SR = srRef,
        virtual_size = 24 * GiB,
        type = vdi_type.system,
        sharable = false,
        read_only = false,
        other_config = new Dictionary<string, string>(),
    }).opaque_ref;
    VBD.create(session, new VBD
    {
        VM = new XenRef<VM>(vm),
        VDI = new XenRef<VDI>(vdi),
        userdevice = vbdDevice,
        bootable = true,
        mode = vbd_mode.RW,
        type = vbd_type.Disk,
        empty = false,
        other_config = new Dictionary<string, string>(),
        qos_algorithm_type = "",
        qos_algorithm_params = new Dictionary<string, string>(),
    });
    Console.WriteLine($"Storage:       24 GiB disk on {sr.name_label}");

    // Page 7 - Networking: attach a VIF to a network.
    var (netRef, net) = Network.get_all_records(session).First();
    var vifDevice = VM.get_allowed_VIF_devices(session, vm)[0];
    VIF.create(session, new VIF
    {
        VM = new XenRef<VM>(vm),
        network = netRef,
        device = vifDevice,
        MAC = "",
        MTU = 1500,
        other_config = new Dictionary<string, string>(),
        qos_algorithm_type = "",
        qos_algorithm_params = new Dictionary<string, string>(),
    });
    Console.WriteLine($"Networking:    NIC on {net.name_label}");

    // Page 8 - Finish: start the VM.
    VM.start(session, vm, false, true);

    Console.WriteLine("--- Result ---");
    Console.WriteLine($"power state:   {VM.get_power_state(session, vm)}");
    Console.WriteLine($"vCPUs:         {VM.get_VCPUs_max(session, vm)}");
    Console.WriteLine($"disks:         {VM.get_VBDs(session, vm).Count}, NICs: {VM.get_VIFs(session, vm).Count}");

    // Tidy up so the example is repeatable.
    VM.hard_shutdown(session, vm);
    VM.destroy(session, vm);
    VDI.destroy(session, vdi);
    Console.WriteLine("Cleaned up the example VM.");

    Console.WriteLine("OK: new-vm-wizard");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Template:      Rocky Linux 8
Created VM:    00000001-0000-0000-ed09-000000000000
Install media: network repository
Home server:   sdk-host1
CPU/memory:    2 vCPUs, 2 GiB
Storage:       24 GiB disk on Shared NFS
Networking:    NIC on Pool-wide network associated with eth0
--- Result ---
power state:   Running
vCPUs:         2
disks:         1, NICs: 1
Cleaned up the example VM.
OK: new-vm-wizard
```

</details>

## Go

Source: [`go/new_vm_wizard.go`](../../go/new_vm_wizard.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// newVMWizard - Create a VM (full workflow).
//
// Create a VM end to end: pick a template, name the VM, choose an installation source and a home
// server, set CPU & memory, add a disk on a storage repository, attach a network interface and
// start it — the full sequence, rather than a single clone call.
//
// Run it:
//
//	newVMWizard("https://xenserver", "root", password, "Rocky Linux 8", "wizard-vm")
func newVMWizard(url, user, password, templateName, newVMName string) {
	const GiB = 1024 * 1024 * 1024
	const MiB = 1024 * 1024

	session := connect(url, user, password)
	// Page 1 - Template.
	templateRef := templateByName(session, templateName)
	tname, _ := xenapi.VM.GetNameLabel(session, templateRef)
	fmt.Printf("Template:      %s\n", tname)

	// Page 2 - Name and description.
	vm, err := xenapi.VM.Clone(session, templateRef, newVMName)
	check(err)
	check(xenapi.VM.SetNameDescription(session, vm, "Created by the full New VM wizard example"))
	check(xenapi.VM.SetIsATemplate(session, vm, false))
	uuid, _ := xenapi.VM.GetUUID(session, vm)
	fmt.Printf("Created VM:    %s\n", uuid)

	// Page 3 - Installation media (a network install repository).
	check(xenapi.VM.AddToOtherConfig(session, vm, "install-repository",
		"http://mirror.example.com/rocky/9/os/x86_64"))
	fmt.Println("Install media: network repository")

	// Page 4 - Home server (affinity).
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var hostRef xenapi.HostRef
	var hostName string
	for ref, h := range hosts {
		hostRef, hostName = ref, h.NameLabel
		break
	}
	check(xenapi.VM.SetAffinity(session, vm, hostRef))
	fmt.Printf("Home server:   %s\n", hostName)

	// Page 5 - CPU & Memory.
	check(xenapi.VM.SetVCPUsMax(session, vm, 2))
	check(xenapi.VM.SetVCPUsAtStartup(session, vm, 2))
	check(xenapi.VM.SetMemoryLimits(session, vm, 512*MiB, 2*GiB, 2*GiB, 2*GiB))
	fmt.Println("CPU/memory:    2 vCPUs, 2 GiB")

	// Page 6 - Storage: add a disk on a (non-ISO) SR.
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var srRef xenapi.SRRef
	var srName string
	for ref, sr := range srs {
		if sr.ContentType != "iso" && sr.Type != "iso" && sr.Type != "udev" {
			srRef, srName = ref, sr.NameLabel
			break
		}
	}
	vbdDevices, err := xenapi.VM.GetAllowedVBDDevices(session, vm)
	check(err)
	vdi, err := xenapi.VDI.Create(session, xenapi.VDIRecord{
		NameLabel:       newVMName + " disk 0",
		NameDescription: "System disk created by the wizard example",
		SR:              srRef,
		VirtualSize:     24 * GiB,
		Type:            xenapi.VdiTypeSystem,
		Sharable:        false,
		ReadOnly:        false,
		OtherConfig:     map[string]string{},
	})
	check(err)
	_, err = xenapi.VBD.Create(session, xenapi.VBDRecord{
		VM: vm, VDI: vdi, Userdevice: vbdDevices[0], Bootable: true,
		Mode: xenapi.VbdModeRW, Type: xenapi.VbdTypeDisk, Empty: false,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
	})
	check(err)
	fmt.Printf("Storage:       24 GiB disk on %s\n", srName)

	// Page 7 - Networking: attach a VIF to a network.
	nets, err := xenapi.Network.GetAllRecords(session)
	check(err)
	var netRef xenapi.NetworkRef
	var netName string
	for ref, n := range nets {
		netRef, netName = ref, n.NameLabel
		break
	}
	vifDevices, err := xenapi.VM.GetAllowedVIFDevices(session, vm)
	check(err)
	// A Go record sends every field, enums included, and a real host rejects an empty enum value
	// (INTERNAL_ERROR "Unknown tag/contents"), so set the enums to the defaults xapi applies when
	// they are left out.
	_, err = xenapi.VIF.Create(session, xenapi.VIFRecord{
		VM: vm, Network: netRef, Device: vifDevices[0], MAC: "", MTU: 1500,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
		LockingMode:           xenapi.VifLockingModeNetworkDefault,
		Ipv4ConfigurationMode: xenapi.VifIpv4ConfigurationModeNone,
		Ipv6ConfigurationMode: xenapi.VifIpv6ConfigurationModeNone,
	})
	check(err)
	fmt.Printf("Networking:    NIC on %s\n", netName)

	// Page 8 - Finish: start the VM.
	check(xenapi.VM.Start(session, vm, false, true))

	fmt.Println("--- Result ---")
	ps, _ := xenapi.VM.GetPowerState(session, vm)
	vcpus, _ := xenapi.VM.GetVCPUsMax(session, vm)
	vbds, _ := xenapi.VM.GetVBDs(session, vm)
	vifs, _ := xenapi.VM.GetVIFs(session, vm)
	fmt.Printf("power state:   %s\n", ps)
	fmt.Printf("vCPUs:         %d\n", vcpus)
	fmt.Printf("disks:         %d, NICs: %d\n", len(vbds), len(vifs))

	// Tidy up so the example is repeatable.
	check(xenapi.VM.HardShutdown(session, vm))
	check(xenapi.VM.Destroy(session, vm))
	check(xenapi.VDI.Destroy(session, vdi))
	fmt.Println("Cleaned up the example VM.")

	fmt.Println("OK: new-vm-wizard")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Template:      Rocky Linux 8
Created VM:    00000001-0000-0000-f609-000000000000
Install media: network repository
Home server:   sdk-host1
CPU/memory:    2 vCPUs, 2 GiB
Storage:       24 GiB disk on Shared NFS
Networking:    NIC on Pool-wide network associated with eth0
--- Result ---
power state:   Running
vCPUs:         2
disks:         1, NICs: 1
Cleaned up the example VM.
OK: new-vm-wizard
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/NewVmWizard.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/NewVmWizard.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class NewVmWizard {
    private NewVmWizard() {
    }

    /**
     * Create a VM (full workflow).
     *
     * <p>Create a VM end to end: pick a template, name the VM, choose an installation source and a home
     * server, set CPU &amp; memory, add a disk on a storage repository, attach a network interface and
     * start it — the full sequence, rather than a single clone call.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * NewVmWizard.run("https://xenserver", "root", password, "Rocky Linux 8", "wizard-vm");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        final long GiB = 1024L * 1024 * 1024, MiB = 1024L * 1024;

        Connection conn = connect(url, user, password);
        // Page 1 - Template.
        VM template = templateByName(conn, templateName);
        System.out.println("Template:      " + template.getNameLabel(conn));

        // Page 2 - Name and description.
        VM vm = template.createClone(conn, newVmName);
        vm.setNameDescription(conn, "Created by the full New VM wizard example");
        vm.setIsATemplate(conn, false);
        System.out.println("Created VM:    " + vm.getUuid(conn));

        // Page 3 - Installation media (a network install repository).
        vm.addToOtherConfig(conn, "install-repository", "http://mirror.example.com/rocky/9/os/x86_64");
        System.out.println("Install media: network repository");

        // Page 4 - Home server (affinity).
        Map.Entry<Host, Host.Record> he = Host.getAllRecords(conn).entrySet().iterator().next();
        vm.setAffinity(conn, he.getKey());
        System.out.println("Home server:   " + he.getValue().nameLabel);

        // Page 5 - CPU & Memory.
        vm.setVCPUsMax(conn, 2L);
        vm.setVCPUsAtStartup(conn, 2L);
        vm.setMemoryLimits(conn, 512 * MiB, 2 * GiB, 2 * GiB, 2 * GiB);
        System.out.println("CPU/memory:    2 vCPUs, 2 GiB");

        // Page 6 - Storage: add a disk on a (non-ISO) SR.
        SR sr = null;
        String srName = null;
        for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet()) {
            if (!"iso".equals(e.getValue().contentType)
                    && !"iso".equals(e.getValue().type) && !"udev".equals(e.getValue().type)) {
                sr = e.getKey();
                srName = e.getValue().nameLabel;
                break;
            }
        }
        VDI.Record vdiRec = new VDI.Record();
        vdiRec.nameLabel = newVmName + " disk 0";
        vdiRec.nameDescription = "System disk created by the wizard example";
        vdiRec.SR = sr;
        vdiRec.virtualSize = 24 * GiB;
        vdiRec.type = Types.VdiType.SYSTEM;
        vdiRec.sharable = false;
        vdiRec.readOnly = false;
        vdiRec.otherConfig = new java.util.HashMap<>();
        VDI vdi = VDI.create(conn, vdiRec);

        VBD.Record vbdRec = new VBD.Record();
        vbdRec.VM = vm;
        vbdRec.VDI = vdi;
        vbdRec.userdevice = vm.getAllowedVBDDevices(conn).iterator().next();
        vbdRec.bootable = true;
        vbdRec.mode = Types.VbdMode.RW;
        vbdRec.type = Types.VbdType.DISK;
        vbdRec.empty = false;
        vbdRec.otherConfig = new java.util.HashMap<>();
        vbdRec.qosAlgorithmType = "";
        vbdRec.qosAlgorithmParams = new java.util.HashMap<>();
        VBD.create(conn, vbdRec);
        System.out.println("Storage:       24 GiB disk on " + srName);

        // Page 7 - Networking: attach a VIF to a network.
        Map.Entry<Network, Network.Record> ne = Network.getAllRecords(conn).entrySet().iterator().next();
        VIF.Record vifRec = new VIF.Record();
        vifRec.VM = vm;
        vifRec.network = ne.getKey();
        vifRec.device = vm.getAllowedVIFDevices(conn).iterator().next();
        vifRec.MAC = "";
        vifRec.MTU = 1500L;
        vifRec.otherConfig = new java.util.HashMap<>();
        vifRec.qosAlgorithmType = "";
        vifRec.qosAlgorithmParams = new java.util.HashMap<>();
        // Left unset, the binding's Record defaults these two enums to its own UNRECOGNIZED sentinel,
        // which released xapi rejects outright rather than treating as "no IP configured". Say so
        // explicitly.
        vifRec.ipv4ConfigurationMode = Types.VifIpv4ConfigurationMode.NONE;
        vifRec.ipv6ConfigurationMode = Types.VifIpv6ConfigurationMode.NONE;
        VIF.create(conn, vifRec);
        System.out.println("Networking:    NIC on " + ne.getValue().nameLabel);

        // Page 8 - Finish: start the VM.
        vm.start(conn, false, true);

        System.out.println("--- Result ---");
        System.out.println("power state:   " + vm.getPowerState(conn));
        System.out.println("vCPUs:         " + vm.getVCPUsMax(conn));
        System.out.println("disks:         " + vm.getVBDs(conn).size() + ", NICs: " + vm.getVIFs(conn).size());

        // Tidy up so the example is repeatable.
        vm.hardShutdown(conn);
        vm.destroy(conn);
        vdi.destroy(conn);
        System.out.println("Cleaned up the example VM.");

        System.out.println("OK: new-vm-wizard");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Template:      Rocky Linux 8
Created VM:    00000001-0000-0000-f709-000000000000
Install media: network repository
Home server:   sdk-host1
CPU/memory:    2 vCPUs, 2 GiB
Storage:       24 GiB disk on Shared NFS
Networking:    NIC on Pool-wide network associated with eth0
--- Result ---
power state:   Running
vCPUs:         2
disks:         1, NICs: 1
Cleaned up the example VM.
OK: new-vm-wizard
```

</details>
