<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage a vApp

Group VMs into an appliance that starts and stops together in a defined order, start and shut it down as a unit, then remove it.

Workflow `manage-vapp`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-ManageVapp.ps1`](../../powershell/VirtualMachines/Invoke-ManageVapp.ps1)

```powershell
function Invoke-ManageVapp {
    <#
    .SYNOPSIS
        Manage a vApp.
    .DESCRIPTION
        Group VMs into an appliance that starts and stops together in a defined order, start and shut it
        down as a unit, then remove it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = "db-01"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName

    $vapp = New-XenVMAppliance -NameLabel "sdk-example-vapp" `
        -NameDescription "Created by the SDK example" -PassThru

    # `order` decides the sequence: ascending to start, descending to shut down. That ordering is the
    # reason to use a vApp rather than selecting several VMs.
    Set-XenVM -VM $vm -Appliance $vapp.opaque_ref
    Set-XenVM -VM $vm -Order 0 -StartDelay 5

    Invoke-XenVMAppliance -VMAppliance $vapp -XenAction Start -Paused $false
    Write-Host "Started:        $((Get-XenVM -Name $VmName).power_state)"

    # Shutdown tries each VM's clean shutdown and falls back to a hard one. CleanShutdown alone fails
    # OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers).
    Invoke-XenVMAppliance -VMAppliance $vapp -XenAction Shutdown
    Write-Host "Shut down:      $((Get-XenVM -Name $VmName).power_state)"

    Set-XenVM -VM (Get-XenVM -Name $VmName) -Appliance "OpaqueRef:NULL"
    Remove-XenVMAppliance -VMAppliance $vapp
    Write-Host "OK: manage-vapp"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Started:        Running
Shut down:      Halted
OK: manage-vapp
```

</details>

## xe CLI

Source: [`cli/virtual-machines/manage-vapp.sh`](../../cli/virtual-machines/manage-vapp.sh)

```bash
# Manage a vApp.
#
# Group VMs into an appliance that starts and stops together in a defined order, start and shut it down as a
# unit, then remove it.
#
# Run it:
#   ./workflows.sh manage-vapp https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (db-01)

manage_vapp() {
    local vm_uuid vapp_uuid
    # A halted VM: an appliance starts only if one of its VMs is halted (OPERATION_NOT_ALLOWED otherwise).
    vm_uuid=$(xe vm-list name-label="$(param vm_name db-01)" --minimal)
    vapp_uuid=$(xe appliance-create name-label=sdk-example-vapp \
        name-description="Created by the SDK example")

    # `order` decides the sequence: ascending to start, descending to shut down. That ordering is the
    # reason to use a vApp rather than selecting several VMs.
    xe vm-param-set uuid="$vm_uuid" appliance="$vapp_uuid" order=0 start-delay=5

    xe appliance-start uuid="$vapp_uuid"
    echo "Started:        $(xe vm-list uuid="$vm_uuid" params=power-state --minimal)"

    # A plain appliance-shutdown tries a clean shutdown of every member and fails
    # OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers);
    # force=true is not a per-member fallback - it hard-shuts-down every member directly - so only
    # reach for it if the clean attempt failed.
    xe appliance-shutdown uuid="$vapp_uuid" || xe appliance-shutdown uuid="$vapp_uuid" force=true
    echo "Shut down:      $(xe vm-list uuid="$vm_uuid" params=power-state --minimal)"

    xe vm-param-set uuid="$vm_uuid" appliance=
    xe appliance-destroy uuid="$vapp_uuid"
    echo "OK: manage-vapp"
}
```

<details><summary>Example output</summary>

```text
Started:        running
Shut down:      halted
OK: manage-vapp
```

</details>

## Python

Source: [`python/virtual_machines/manage_vapp.py`](../../python/virtual_machines/manage_vapp.py)

```python
"""Manage a vApp.

Group VMs into an appliance that starts and stops together in a defined order, start and shut it
down as a unit, then remove it.

Run it::

    manage_vapp("https://xenserver", "root", password, "db-01")
"""

from connection import connect


def manage_vapp(url, username, password, vm_name):
    """Group VMs into an appliance that starts and stops together, then remove it."""
    session = connect(url, username, password)
    x = session.xenapi
    vm = x.VM.get_by_name_label(vm_name)[0]

    vapp = x.VM_appliance.create({
        "name_label": "sdk-example-vapp",
        "name_description": "Created by the SDK example",
    })

    # `order` decides the sequence: ascending to start, descending to shut down. That ordering is the
    # reason to use a vApp at all rather than selecting several VMs.
    x.VM.set_appliance(vm, vapp)
    x.VM.set_order(vm, "0")
    x.VM.set_start_delay(vm, "5")

    x.VM_appliance.start(vapp, False)
    print(f"Started:        {x.VM.get_power_state(vm)}")

    # shutdown tries each VM's clean shutdown and falls back to a hard one. clean_shutdown alone fails
    # OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers).
    x.VM_appliance.shutdown(vapp)
    print(f"Shut down:      {x.VM.get_power_state(vm)}")

    x.VM.set_appliance(vm, "OpaqueRef:NULL")
    x.VM_appliance.destroy(vapp)
    print("OK: manage-vapp")
    x.session.logout()
```

<details><summary>Example output</summary>

```text
Started:        Running
Shut down:      Halted
OK: manage-vapp
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/ManageVapp.cs`](../../csharp/VirtualMachines/ManageVapp.cs)

```csharp
/// <summary>
/// Group VMs into an appliance that starts and stops together in a defined order, start and shut it down
/// as a unit, then remove it.
/// </summary>
/// <example>
/// <code>
/// Workflows.ManageVapp("https://xenserver", "root", password, "db-01");
/// </code>
/// </example>
public static void ManageVapp(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);
    var vm = VM.get_by_name_label(session, vmName)[0];

    var vapp = VM_appliance.create(session, new VM_appliance
    {
        name_label = "sdk-example-vapp",
        name_description = "Created by the SDK example",
    });

    // `order` decides the sequence: ascending to start, descending to shut down. That ordering is the
    // reason to use a vApp at all rather than selecting several VMs — the database comes up first and
    // goes down last.
    VM.set_appliance(session, vm.opaque_ref, vapp.opaque_ref);
    VM.set_order(session, vm.opaque_ref, 0);
    VM.set_start_delay(session, vm.opaque_ref, 5);

    VM_appliance.start(session, vapp.opaque_ref, false);
    Console.WriteLine($"Started:        {VM.get_power_state(session, vm.opaque_ref)}");

    // shutdown tries each VM's clean shutdown and falls back to a hard one. clean_shutdown alone fails
    // OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers).
    VM_appliance.shutdown(session, vapp.opaque_ref);
    Console.WriteLine($"Shut down:      {VM.get_power_state(session, vm.opaque_ref)}");

    VM.set_appliance(session, vm.opaque_ref, "OpaqueRef:NULL"); // the null reference, spelled out: null would send ""
    VM_appliance.destroy(session, vapp.opaque_ref);
    Console.WriteLine("OK: manage-vapp");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Started:        Running
Shut down:      Halted
OK: manage-vapp
```

</details>

## Go

Source: [`go/manage_vapp.go`](../../go/manage_vapp.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// manageVapp - Manage a vApp.
//
// Group VMs into an appliance that starts and stops together in a defined order, start and shut it
// down as a unit, then remove it.
func manageVapp(url, user, password, vmName string) {
	session := connect(url, user, password)
	vms, err := xenapi.VM.GetByNameLabel(session, vmName)
	check(err)
	vm := vms[0]

	vapp, err := xenapi.VMAppliance.Create(session, xenapi.VMApplianceRecord{
		NameLabel:       "sdk-example-vapp",
		NameDescription: "Created by the SDK example",
	})
	check(err)

	// `order` decides the sequence: ascending to start, descending to shut down. That ordering is the
	// reason to use a vApp rather than selecting several VMs.
	check(xenapi.VM.SetAppliance(session, vm, vapp))
	check(xenapi.VM.SetOrder(session, vm, 0))
	check(xenapi.VM.SetStartDelay(session, vm, 5))

	check(xenapi.VMAppliance.Start(session, vapp, false))
	state, _ := xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Started:        %s\n", state)

	// Shutdown tries each VM's clean shutdown and falls back to a hard one. CleanShutdown alone fails
	// OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers).
	check(xenapi.VMAppliance.Shutdown(session, vapp))
	state, _ = xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Shut down:      %s\n", state)

	check(xenapi.VM.SetAppliance(session, vm, "OpaqueRef:NULL")) // the null reference: "" is not one
	check(xenapi.VMAppliance.Destroy(session, vapp))
	fmt.Println("OK: manage-vapp")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Started:        Running
Shut down:      Halted
OK: manage-vapp
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/ManageVapp.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/ManageVapp.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VMAppliance;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVapp {
    private ManageVapp() {
    }

    /**
     * Manage a vApp.
     *
     * <p>Group VMs into an appliance that starts and stops together in a defined order, start and shut it
     * down as a unit, then remove it.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageVapp.run("https://xenserver", "root", password, "db-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = VM.getByNameLabel(conn, vmName).iterator().next();

            VMAppliance.Record spec = new VMAppliance.Record();
            spec.nameLabel = "sdk-example-vapp";
            spec.nameDescription = "Created by the SDK example";
            VMAppliance vapp = VMAppliance.create(conn, spec);

            // `order` decides the sequence: ascending to start, descending to shut down. That ordering
            // is the reason to use a vApp rather than selecting several VMs.
            vm.setAppliance(conn, vapp);
            vm.setOrder(conn, 0L);
            vm.setStartDelay(conn, 5L);

            vapp.start(conn, false);
            System.out.println("Started:        " + vm.getPowerState(conn));

            // shutdown tries each VM's clean shutdown and falls back to a hard one. cleanShutdown alone
            // fails OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers).
            vapp.shutdown(conn);
            System.out.println("Shut down:      " + vm.getPowerState(conn));

            // Detach with the null REFERENCE, not Java's null: the binding doesn't turn null into
            // OpaqueRef:NULL, and a real host refuses what it sends with INTERNAL_ERROR.
            vm.setAppliance(conn, new VMAppliance("OpaqueRef:NULL"));
            vapp.destroy(conn);
            System.out.println("OK: manage-vapp");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
Started:        Running
Shut down:      Halted
OK: manage-vapp
```

</details>
