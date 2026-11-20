<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Checkpoint & revert

Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must have a guest OS with PV drivers and have finished booting (vm_name).

**Caution:** suspends the named VM, reverts it to the checkpoint and resumes it; changes made in the guest since the checkpoint are lost.

Workflow `checkpoint-vm`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-CheckpointVm.ps1`](../../powershell/VirtualMachines/Invoke-CheckpointVm.ps1)

```powershell
function Invoke-CheckpointVm {
    <#
    .SYNOPSIS
        Checkpoint & revert.
    .DESCRIPTION
        Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
        you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must
        have a guest OS with PV drivers (vm_name).
    .EXAMPLE
        Invoke-CheckpointVm -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
    # Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest freezes
    # its processes and suspends itself. A guest that is still booting can fail to freeze a process that is
    # busy starting up, and it then abandons the suspend without telling the host, which waits until
    # VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here.
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    if ($vm.power_state -ne 'Running') { throw "$VmName must be running to be checkpointed" }
    $ref = $vm.opaque_ref
    # Running is not enough: the VM may have just been started (or restarted, as snapshot-revert does), so
    # wait for its guest to finish booting first.
    Wait-GuestAgent -Ref $ref

    $checkpoint = $vm | Invoke-XenVM -XenAction Checkpoint -NewName "sdk-example-checkpoint-1" -PassThru
    Write-Host "Created checkpoint: $($checkpoint.uuid)"
    Write-Host "is_a_snapshot = $($checkpoint.is_a_snapshot)"

    $vm | Invoke-XenVM -XenAction Revert -Snapshot $checkpoint
    # A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
    # Revert restores exactly that - so the VM is Suspended here, not Running as it was before the
    # checkpoint, with a suspend_VDI holding the checkpoint's memory image. Resume picks up from there
    # (and frees that memory image).
    Write-Host "Reverted $VmName to the checkpoint; power state now: $((Get-XenVM -Ref $ref).power_state)"
    $vm | Invoke-XenVM -XenAction Resume
    Write-Host "Resumed $VmName; power state now: $((Get-XenVM -Ref $ref).power_state)"

    # Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
    Remove-VmAndDisks -Ref $checkpoint
    Write-Host "Deleted the checkpoint."
    Write-Host "OK: checkpoint-vm"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-f709-000000000000
is_a_snapshot = True
Reverted web-01 to the checkpoint; power state now: Suspended
Resumed web-01; power state now: Running
Deleted the checkpoint.
OK: checkpoint-vm
```

</details>

## xe CLI

Source: [`cli/virtual-machines/checkpoint-vm.sh`](../../cli/virtual-machines/checkpoint-vm.sh)

```bash
# Checkpoint & revert.
#
# Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you would
# before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must have a guest OS
# with PV drivers (vm_name).
#
# Run it:
#   ./workflows.sh checkpoint-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (web-01)

# Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest freezes its
# processes and suspends itself. A guest that is still booting can fail to freeze a process that is busy
# starting up, and it then abandons the suspend without telling the host, which waits until
# VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here.
checkpoint_vm() {
    local vm_name=$(param vm_name "web-01")
    vm=$(vm_uuid "$vm_name")
    if [ "$(remote_xe vm-param-get uuid=$vm param-name=power-state)" != "running" ]; then
        echo "$vm_name must be running to be checkpointed" >&2
        return 1
    fi
    # Running is not enough: the VM may have just been started (or restarted, as snapshot-revert does), so
    # wait for its guest to finish booting first.
    wait_for_guest_agent "$vm"
    cp=$(remote_xe vm-checkpoint uuid=$vm new-name-label=xe-example-checkpoint-1)
    echo "Created checkpoint: $cp"
    remote_xe snapshot-revert snapshot-uuid=$cp
    # A checkpoint's own power-state is always Suspended (it captures memory as well as disk), and
    # snapshot-revert restores exactly that - so the VM is Suspended here, not Running as it was before
    # the checkpoint, with a suspend-VDI holding the checkpoint's memory image. vm-resume picks up from
    # there (and frees that memory image).
    echo "Reverted $vm_name to the checkpoint; power-state now: $(remote_xe vm-param-get uuid=$vm param-name=power-state)"
    remote_xe vm-resume uuid=$vm
    echo "Resumed $vm_name; power-state now: $(remote_xe vm-param-get uuid=$vm param-name=power-state)"
    # Tidy up so the example is repeatable. The checkpoint owns its own snapshot disks (and memory
    # image), separate from the VM's; snapshot-uninstall destroys them with the record.
    remote_xe snapshot-uninstall snapshot-uuid=$cp force=true
    echo "Deleted the checkpoint."
    ok checkpoint-vm
}
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-f609-000000000000
Reverted web-01 to the checkpoint; power-state now: suspended
Resumed web-01; power-state now: running
The following items are about to be destroyed
VM : 00000001-0000-0000-f609-000000000000 (xe-example-checkpoint-1)
VDI: 00000001-0000-0000-f709-000000000000 (web-01 root disk) 
All objects destroyed
Deleted the checkpoint.
OK: checkpoint-vm
```

</details>

## Python

Source: [`python/virtual_machines/checkpoint_vm.py`](../../python/virtual_machines/checkpoint_vm.py)

```python
"""Checkpoint & revert.

Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must
have a guest OS with PV drivers (vm_name).

Run it::

    checkpoint_vm("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name, wait_for_guest_agent


def checkpoint_vm(url, username, password, vm_name):
    """A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
    Checkpoint vm_name, revert it to that checkpoint, and resume it.

    Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest
    freezes its processes and suspends itself. A guest that is still booting can fail to freeze a
    process that is busy starting up, and it then abandons the suspend without telling the host, which
    waits until VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    if session.xenapi.VM.get_power_state(vm) != "Running":
        raise RuntimeError("%s must be running to be checkpointed" % vm_name)
    # Running is not enough: the VM may have just been started (or restarted, as snapshot-revert does), so
    # wait for its guest to finish booting first.
    wait_for_guest_agent(session, vm)

    checkpoint = session.xenapi.VM.checkpoint(vm, "sdk-example-checkpoint-1")
    print("Created checkpoint: %s" % session.xenapi.VM.get_uuid(checkpoint))
    print("is_a_snapshot = %s" % session.xenapi.VM.get_is_a_snapshot(checkpoint))

    session.xenapi.VM.revert(checkpoint)
    # A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
    # VM.revert restores exactly that - so the VM is Suspended here, not Running as it was before
    # the checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.resume picks up
    # from there (and frees that memory image).
    print("Reverted %s to the checkpoint; power state now: %s"
          % (vm_name, session.xenapi.VM.get_power_state(vm)))
    session.xenapi.VM.resume(vm, False, True)
    print("Resumed %s; power state now: %s" % (vm_name, session.xenapi.VM.get_power_state(vm)))

    # Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
    destroy_vm_and_disks(session, checkpoint)
    print("Deleted the checkpoint.")
    print("OK: checkpoint-vm")
    session.logout()
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-f709-000000000000
is_a_snapshot = True
Reverted web-01 to the checkpoint; power state now: Suspended
Resumed web-01; power state now: Running
Deleted the checkpoint.
OK: checkpoint-vm
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/CheckpointVm.cs`](../../csharp/VirtualMachines/CheckpointVm.cs)

```csharp
/// <summary>
/// Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you
/// would before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must have a
/// guest OS with PV drivers (vm_name).
/// </summary>
/// <example>
/// <code>
/// Workflows.CheckpointVm("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void CheckpointVm(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);
    // A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
    // Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest
    // freezes its processes and suspends itself. A guest that is still booting can fail to freeze a
    // process that is busy starting up, and it then abandons the suspend without telling the host, which
    // waits until VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here.
    var vm = VmByName(session, vmName);
    if (VM.get_power_state(session, vm) != vm_power_state.Running)
        throw new InvalidOperationException($"{vmName} must be running to be checkpointed");
    // Running is not enough: the VM may have just been started (or restarted, as snapshot-revert does), so
    // wait for its guest to finish booting first.
    WaitForGuestAgent(session, vm);

    var checkpoint = VM.checkpoint(session, vm, "sdk-example-checkpoint-1");
    Console.WriteLine($"Created checkpoint: {VM.get_uuid(session, checkpoint)}");
    Console.WriteLine($"is_a_snapshot = {VM.get_is_a_snapshot(session, checkpoint)}");

    // A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
    // VM.revert restores exactly that - so the VM is Suspended here, not Running as it was before the
    // checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.resume picks up from there
    // (and frees that memory image).
    VM.revert(session, checkpoint);
    Console.WriteLine($"Reverted {vmName} to the checkpoint; power state now: {VM.get_power_state(session, vm)}");
    VM.resume(session, vm, false, true);
    Console.WriteLine($"Resumed {vmName}; power state now: {VM.get_power_state(session, vm)}");

    // Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
    DestroyVmAndDisks(session, checkpoint);
    Console.WriteLine("Deleted the checkpoint.");
    Console.WriteLine("OK: checkpoint-vm");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-f709-000000000000
is_a_snapshot = True
Reverted web-01 to the checkpoint; power state now: Suspended
Resumed web-01; power state now: Running
Deleted the checkpoint.
OK: checkpoint-vm
```

</details>

## Go

Source: [`go/checkpoint_vm.go`](../../go/checkpoint_vm.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// checkpointVM checkpoints a running VM with a guest OS, reverts it to that checkpoint and resumes
// it. A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
// Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest
// freezes its processes and suspends itself. A guest that is still booting can fail to freeze a
// process that is busy starting up, and it then abandons the suspend without telling the host, which
// waits until VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here.
//
// Run it:
//
//	checkpointVM("https://xenserver", "root", password, "web-01")
func checkpointVM(url, user, password, vmName string) {
	session := connect(url, user, password)
	defer session.Logout()
	vm := vmByName(session, vmName)
	state, err := xenapi.VM.GetPowerState(session, vm)
	check(err)
	if state != xenapi.VMPowerStateRunning {
		panic(fmt.Sprintf("%s must be running to be checkpointed", vmName))
	}
	// Running is not enough: the VM may have just been started (or restarted, as snapshot-revert does),
	// so wait for its guest to finish booting first.
	waitForGuestAgent(session, vm)

	checkpoint, err := xenapi.VM.Checkpoint(session, vm, "sdk-example-checkpoint-1")
	check(err)
	uuid, _ := xenapi.VM.GetUUID(session, checkpoint)
	fmt.Printf("Created checkpoint: %s\n", uuid)
	isSnapshot, _ := xenapi.VM.GetIsASnapshot(session, checkpoint)
	fmt.Printf("is_a_snapshot = %v\n", isSnapshot)

	check(xenapi.VM.Revert(session, checkpoint))
	// A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
	// VM.Revert restores exactly that - so the VM is Suspended here, not Running as it was before
	// the checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.Resume picks up
	// from there (and frees that memory image).
	ps, _ := xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Reverted %s to the checkpoint; power state now: %s\n", vmName, ps)
	check(xenapi.VM.Resume(session, vm, false, true))
	ps, _ = xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Resumed %s; power state now: %s\n", vmName, ps)

	// Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
	destroyVMAndDisks(session, checkpoint)
	fmt.Println("Deleted the checkpoint.")
	fmt.Println("OK: checkpoint-vm")
}
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-f709-000000000000
is_a_snapshot = true
Reverted web-01 to the checkpoint; power state now: Suspended
Resumed web-01; power state now: Running
Deleted the checkpoint.
OK: checkpoint-vm
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/CheckpointVm.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/CheckpointVm.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class CheckpointVm {
    private CheckpointVm() {
    }

    /**
     * Checkpoint &amp; revert.
     *
     * <p>Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
     * you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must
     * have a guest OS with PV drivers (vm_name).
     *
     * <p>Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest
     * freezes its processes and suspends itself. A guest that is still booting can fail to freeze a process
     * that is busy starting up, and it then abandons the suspend without telling the host, which waits until
     * VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CheckpointVm.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        // A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
        VM vm = vmByName(conn, vmName);
        if (vm.getPowerState(conn) != Types.VmPowerState.RUNNING) {
            throw new IllegalStateException(vmName + " must be running to be checkpointed");
        }
        // Running is not enough: the VM may have just been started (or restarted, as snapshot-revert does),
        // so wait for its guest to finish booting first.
        waitForGuestAgent(conn, vm);

        VM checkpoint = vm.checkpoint(conn, "sdk-example-checkpoint-1");
        System.out.println("Created checkpoint: " + checkpoint.getUuid(conn));
        System.out.println("is_a_snapshot = " + checkpoint.getIsASnapshot(conn));

        checkpoint.revert(conn);
        // A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
        // revert restores exactly that - so the VM is Suspended here, not Running as it was before the
        // checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.resume picks up from
        // there (and frees that memory image).
        System.out.println("Reverted " + vmName + " to the checkpoint; power state now: " + vm.getPowerState(conn));
        vm.resume(conn, false, true);
        System.out.println("Resumed " + vmName + "; power state now: " + vm.getPowerState(conn));

        // Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
        destroyVmAndDisks(conn, checkpoint);
        System.out.println("Deleted the checkpoint.");
        System.out.println("OK: checkpoint-vm");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-f709-000000000000
is_a_snapshot = true
Reverted web-01 to the checkpoint; power state now: Suspended
Resumed web-01; power state now: Running
Deleted the checkpoint.
OK: checkpoint-vm
```

</details>
