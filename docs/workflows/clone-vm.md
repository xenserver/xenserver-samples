<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Clone a VM

Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy — the quick way to stamp out new VMs from a halted "golden" image.

Workflow `clone-vm`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-CloneVm.ps1`](../../powershell/VirtualMachines/Invoke-CloneVm.ps1)

```powershell
function Invoke-CloneVm {
    <#
    .SYNOPSIS
        Clone a VM.
    .DESCRIPTION
        Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy —
        the quick way to stamp out new VMs from a halted "golden" image.
    .EXAMPLE
        Invoke-CloneVm -Url https://xenserver -UserName root -Password $password -VmName 'db-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName,
        [string]$CloneName = "sdk-example-clone"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Unlike Copy (a full, independent copy onto a chosen SR), Clone is a fast copy-on-write
    # duplicate on the same SR - ideal for a halted "golden" VM.
    $source = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $source) { throw "No VM named '$VmName' was found." }

    # VM.clone (like VM.copy) only works on a Halted VM - a running source fails with
    # VM_BAD_POWER_STATE - so shut it down first if it's running, and start it back up again after the
    # clone, rather than assuming the VM is already halted.
    $wasRunning = (Get-XenVM -Ref $source).power_state -eq 'Running'
    if ($wasRunning) { $source | Invoke-XenVM -XenAction CleanShutdown }

    $clone = $source | Invoke-XenVM -XenAction Clone -NewName $CloneName -PassThru
    Write-Host "Cloned '$($source.name_label)' -> $($clone.name_label)"
    Write-Host "Clone has $(@($clone.VBDs).Count) VBD(s)"

    if ($wasRunning) { $source | Invoke-XenVM -XenAction Start }

    # Tidy up: destroy the clone and its (owned) disks.
    Remove-VmAndDisks -Ref $clone
    Write-Host "OK: clone-vm"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Cloned 'db-01' -> sdk-example-clone
Clone has 1 VBD(s)
OK: clone-vm
```

</details>

## xe CLI

Source: [`cli/virtual-machines/clone-vm.sh`](../../cli/virtual-machines/clone-vm.sh)

```bash
# Clone a VM.
#
# Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy — the
# quick way to stamp out new VMs from a halted "golden" image.
#
# Run it:
#   ./workflows.sh clone-vm https://xenserver root "$password"

clone_vm() {
    local vm was_running
    vm=$(vm_uuid db-01)
    # vm-clone (like vm-copy) only works on a Halted VM - a running source fails with VM_BAD_POWER_STATE -
    # so shut it down first if it's running, and start it back up again after the clone.
    was_running=$([ "$(xe vm-param-get uuid=$vm param-name=power-state)" = "running" ] && echo true || echo false)
    [ "$was_running" = true ] && xe vm-shutdown uuid=$vm
    clone=$(xe vm-clone uuid=$vm new-name-label=xe-example-clone)
    echo "Cloned VM: $clone"
    [ "$was_running" = true ] && xe vm-start uuid=$vm
    # Tidy up: vm-uninstall destroys the clone and the disks it owns (vm-destroy would leave them).
    xe vm-uninstall uuid=$clone force=true
    echo "OK: clone-vm"
}
```

<details><summary>Example output</summary>

```text
Cloned VM: 00000001-0000-0000-f909-000000000000
OK: clone-vm
```

</details>

## Python

Source: [`python/virtual_machines/clone_vm.py`](../../python/virtual_machines/clone_vm.py)

```python
"""Clone a VM.

Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy —
the quick way to stamp out new VMs from a halted "golden" image.

Run it::

    clone_vm("https://xenserver", "root", password, "db-01")
"""

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name


def clone_vm(url, username, password, vm_name, clone_name="sdk-example-clone"):
    """Fast copy-on-write clone of a halted VM (unlike Copy, which is a full, independent copy
    onto a chosen SR). Ideal for duplicating a halted "golden" VM on the same SR.

    VM.clone (like VM.copy) only works on a Halted VM - a running source fails with
    VM_BAD_POWER_STATE - so shut it down first if it's running, and start it back up again after
    the clone, rather than assuming the VM is already halted."""
    session = connect(url, username, password)
    source = vm_by_name(session, vm_name)

    was_running = session.xenapi.VM.get_power_state(source) == "Running"
    if was_running:
        session.xenapi.VM.clean_shutdown(source)

    clone = session.xenapi.VM.clone(source, clone_name)
    print("Cloned '%s' -> %s"
          % (session.xenapi.VM.get_name_label(source), session.xenapi.VM.get_name_label(clone)))
    print("Clone has %d VBD(s)" % len(session.xenapi.VM.get_VBDs(clone)))

    if was_running:
        session.xenapi.VM.start(source, False, True)

    # Tidy up: destroy the clone and its (owned) disks.
    destroy_vm_and_disks(session, clone)
    print("OK: clone-vm")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Cloned 'db-01' -> sdk-example-clone
Clone has 1 VBD(s)
OK: clone-vm
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/CloneVm.cs`](../../csharp/VirtualMachines/CloneVm.cs)

```csharp
/// <summary>
/// Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy —
/// the quick way to stamp out new VMs from a halted "golden" image.
/// </summary>
/// <example>
/// <code>
/// Workflows.CloneVm("https://xenserver", "root", password, "db-01");
/// </code>
/// </example>
public static void CloneVm(string url, string user, string password,
    string vmName, string cloneName = "sdk-example-clone")
{
    var session = Connect(url, user, password);
    // Unlike Copy (a full, independent copy onto a chosen SR), Clone is a fast copy-on-write
    // duplicate on the same SR — ideal for a halted "golden" VM.
    // VM.clone (like VM.copy) raises VM_BAD_POWER_STATE on a running source, so shut it down
    // first if it's running, and start it back up again after the clone.
    var source = VmByName(session, vmName);

    var wasRunning = VM.get_power_state(session, source) == vm_power_state.Running;
    if (wasRunning) VM.clean_shutdown(session, source);

    var clone = VM.clone(session, source, cloneName);
    Console.WriteLine($"Cloned '{VM.get_name_label(session, source)}' → {VM.get_name_label(session, clone)}");
    Console.WriteLine($"Clone has {VM.get_VBDs(session, clone).Count} VBD(s)");

    if (wasRunning) VM.start(session, source, false, true);

    // Tidy up: destroy the clone and its (owned) disks.
    DestroyVmAndDisks(session, clone);
    Console.WriteLine("OK: clone-vm");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Cloned 'db-01'  sdk-example-clone
Clone has 1 VBD(s)
OK: clone-vm
```

</details>

## Go

Source: [`go/clone_vm.go`](../../go/clone_vm.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// cloneVM - Clone a VM.
//
// Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full
// copy — the quick way to stamp out new VMs from a halted "golden" image.
//
// Run it:
//
//	cloneVM("https://xenserver", "root", password, "db-01", "sdk-example-clone")
func cloneVM(url, user, password, vmName, cloneName string) {
	session := connect(url, user, password)
	// Unlike Copy (a full, independent copy onto a chosen SR), Clone is a fast copy-on-write
	// duplicate on the same SR - ideal for a halted "golden" VM.
	source := vmByName(session, vmName)

	// VM.Clone (like VM.Copy) requires a Halted source - VM_BAD_POWER_STATE otherwise - so shut a
	// running source down first and start it back up again afterwards, rather than assuming it is
	// already halted.
	wasRunning := false
	if state, _ := xenapi.VM.GetPowerState(session, source); state == xenapi.VMPowerStateRunning {
		wasRunning = true
		check(xenapi.VM.CleanShutdown(session, source))
	}

	clone, err := xenapi.VM.Clone(session, source, cloneName)
	check(err)
	srcName, _ := xenapi.VM.GetNameLabel(session, source)
	cloneLabel, _ := xenapi.VM.GetNameLabel(session, clone)
	fmt.Printf("Cloned '%s' -> %s\n", srcName, cloneLabel)
	vbds, _ := xenapi.VM.GetVBDs(session, clone)
	fmt.Printf("Clone has %d VBD(s)\n", len(vbds))

	if wasRunning {
		check(xenapi.VM.Start(session, source, false, true))
	}

	// Tidy up: destroy the clone and its (owned) disks.
	destroyVMAndDisks(session, clone)
	fmt.Println("OK: clone-vm")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Cloned 'db-01' -> sdk-example-clone
Clone has 1 VBD(s)
OK: clone-vm
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/CloneVm.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/CloneVm.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CloneVm {
    private CloneVm() {
    }

    /**
     * Clone a VM.
     *
     * <p>Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full
     * copy — the quick way to stamp out new VMs from a halted "golden" image.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CloneVm.run("https://xenserver", "root", password, "db-01", "sdk-example-clone");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String vmName, String cloneName) throws Exception {
        Connection conn = connect(url, user, password);
        // Unlike Copy (a full, independent copy onto a chosen SR), Clone is a fast copy-on-write
        // duplicate on the same SR — ideal for a halted "golden" VM.
        VM source = vmByName(conn, vmName);

        // VM.clone (like VM.copy) requires a Halted source (VM_BAD_POWER_STATE otherwise).
        boolean wasRunning = source.getPowerState(conn) == Types.VmPowerState.RUNNING;
        if (wasRunning) source.cleanShutdown(conn);

        VM clone = source.createClone(conn, cloneName);
        System.out.println("Cloned '" + source.getNameLabel(conn) + "' → " + clone.getNameLabel(conn));
        System.out.println("Clone has " + clone.getVBDs(conn).size() + " VBD(s)");

        if (wasRunning) source.start(conn, false, true);

        // Tidy up: destroy the clone and its (owned) disks.
        destroyVmAndDisks(conn, clone);
        System.out.println("OK: clone-vm");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Cloned 'db-01' ? sdk-example-clone
Clone has 1 VBD(s)
OK: clone-vm
```

</details>
