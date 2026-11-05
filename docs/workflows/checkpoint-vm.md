<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Checkpoint & revert

Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works on a throwaway copy of a VM with a guest OS and PV drivers (source_vm).

Workflow `checkpoint-vm`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/VirtualMachines/CheckpointVm.cs`](../../csharp/VirtualMachines/CheckpointVm.cs)

```csharp
/// <summary>
/// Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you
/// would before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works on a
/// throwaway copy of a VM with a guest OS and PV drivers (source_vm).
/// </summary>
/// <example>
/// <code>
/// Workflows.CheckpointVm("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void CheckpointVm(string url, string user, string password,
    string sourceVm, string newVmName = "sdk-example-checkpoint")
{
    var session = Connect(url, user, password);
    // A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
    // Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), hence a
    // copy of sourceVm - a VM with a guest OS and PV drivers - rather than an OS-less template
    // clone.
    var vm = CopyOfGuest(session, sourceVm, newVmName);
    VM.start(session, vm, false, true);
    WaitForGuestAgent(session, vm);

    var checkpoint = VM.checkpoint(session, vm, "sdk-example-checkpoint-1").opaque_ref;
    Console.WriteLine($"Created checkpoint: {VM.get_uuid(session, checkpoint)}");
    Console.WriteLine($"is_a_snapshot = {VM.get_is_a_snapshot(session, checkpoint)}");

    // A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
    // VM.revert restores exactly that - so the VM is Suspended here, not Running as it was before
    // the checkpoint, with a suspend_VDI holding the checkpoint's memory image. Always resume
    // (never a bare "if Running: hard_shutdown" check, which never fires since the VM is never
    // Running here) before destroying it, or the suspend_VDI leaks as a storage orphan.
    VM.revert(session, checkpoint);
    Console.WriteLine($"Reverted the VM to the checkpoint; power state now: {VM.get_power_state(session, vm)}");
    VM.resume(session, vm, false, true);

    // Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
    DestroyVmAndDisks(session, checkpoint);
    VM.hard_shutdown(session, vm);
    DestroyVmAndDisks(session, vm);
    Console.WriteLine("OK: checkpoint-vm");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-6f0a-000000000000
is_a_snapshot = True
Reverted the VM to the checkpoint; power state now: Suspended
OK: checkpoint-vm
```

</details>

## Python

Source: [`python/virtual_machines/checkpoint_vm.py`](../../python/virtual_machines/checkpoint_vm.py)

```python
"""Checkpoint & revert.

Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works
on a throwaway copy of a VM with a guest OS and PV drivers (source_vm).

Run it::

    checkpoint_vm("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, wait_for_guest_agent


def checkpoint_vm(url, username, password, source_vm, new_vm_name="sdk-example-checkpoint"):
    """A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
    Checkpoint a throwaway copy of a VM with a guest OS, then revert it back to that checkpoint.

    Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), hence a copy
    of source_vm - a VM with a guest OS and PV drivers - rather than an OS-less template clone."""
    session = connect(url, username, password)
    vm = copy_of_guest(session, source_vm, new_vm_name)
    session.xenapi.VM.start(vm, False, True)
    wait_for_guest_agent(session, vm)

    checkpoint = session.xenapi.VM.checkpoint(vm, "sdk-example-checkpoint-1")
    print("Created checkpoint: %s" % session.xenapi.VM.get_uuid(checkpoint))
    print("is_a_snapshot = %s" % session.xenapi.VM.get_is_a_snapshot(checkpoint))

    session.xenapi.VM.revert(checkpoint)
    # A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
    # VM.revert restores exactly that - so the VM is Suspended here, not Running as it was before
    # the checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.resume clears
    # that: destroying a Suspended VM directly (as a bare "if Running: hard_shutdown" check would,
    # since the VM is never Running here) leaves that suspend_VDI behind as a storage leak.
    print("Reverted the VM to the checkpoint; power state now: %s"
          % session.xenapi.VM.get_power_state(vm))
    session.xenapi.VM.resume(vm, False, True)

    # Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
    destroy_vm_and_disks(session, checkpoint)
    session.xenapi.VM.hard_shutdown(vm)
    destroy_vm_and_disks(session, vm)
    print("OK: checkpoint-vm")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-460a-000000000000
is_a_snapshot = True
Reverted the VM to the checkpoint; power state now: Suspended
OK: checkpoint-vm
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/CheckpointVm.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/CheckpointVm.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class CheckpointVm {
    private CheckpointVm() {
    }

    /**
     * Checkpoint &amp; revert.
     *
     * <p>Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
     * you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works
     * on a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
     *
     * <p>Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), hence a copy
     * of sourceVm - a VM with a guest OS and PV drivers - rather than an OS-less template clone.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CheckpointVm.run("https://xenserver", "root", password, "web-01", "sdk-example-checkpoint");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String sourceVm, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        // A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
        VM vm = copyOfGuest(conn, sourceVm, newVmName);
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);

        VM checkpoint = vm.checkpoint(conn, "sdk-example-checkpoint-1");
        System.out.println("Created checkpoint: " + checkpoint.getUuid(conn));
        System.out.println("is_a_snapshot = " + checkpoint.getIsASnapshot(conn));

        checkpoint.revert(conn);
        // A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
        // revert restores exactly that - so the VM is Suspended here, not Running as it was before the
        // checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.resume clears that:
        // destroying a Suspended VM directly (as a bare "if Running: hardShutdown" check would, since the
        // VM is never Running here) leaves that suspend_VDI behind as a storage leak.
        System.out.println("Reverted the VM to the checkpoint; power state now: " + vm.getPowerState(conn));
        vm.resume(conn, false, true);

        // Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
        destroyVmAndDisks(conn, checkpoint);
        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: checkpoint-vm");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-560a-000000000000
is_a_snapshot = true
Reverted the VM to the checkpoint; power state now: Suspended
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

// checkpointVM checkpoints a throwaway copy of a VM with a guest OS, then reverts it back to that
// checkpoint. A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be
// running. Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
// hence a copy of sourceVM - a VM with a guest OS and PV drivers - rather than an OS-less template
// clone.
//
// Run it:
//
//	checkpointVM("https://xenserver", "root", password, "web-01", "sdk-example-checkpoint")
func checkpointVM(url, user, password, sourceVM, newVMName string) {
	session := connect(url, user, password)
	vm := copyOfGuest(session, sourceVM, newVMName)
	check(xenapi.VM.Start(session, vm, false, true))
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
	// the checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.Resume clears
	// that: destroying a Suspended VM directly (as a bare "if Running: hard_shutdown" guard would,
	// since the VM is never Running here) leaves that suspend_VDI behind as a storage leak.
	ps, _ := xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Reverted the VM to the checkpoint; power state now: %s\n", ps)
	check(xenapi.VM.Resume(session, vm, false, true))

	// Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
	destroyVMAndDisks(session, checkpoint)
	check(xenapi.VM.HardShutdown(session, vm))
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: checkpoint-vm")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-890a-000000000000
is_a_snapshot = true
Reverted the VM to the checkpoint; power state now: Suspended
OK: checkpoint-vm
```

</details>

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-CheckpointVm.ps1`](../../powershell/VirtualMachines/Invoke-CheckpointVm.ps1)

```powershell
function Invoke-CheckpointVm {
    <#
    .SYNOPSIS
        Checkpoint & revert.
    .DESCRIPTION
        Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
        you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works
        on a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
    .EXAMPLE
        Invoke-CheckpointVm -Url https://xenserver -UserName root -Password $password -SourceVm 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [string]$NewVmName = "sdk-example-checkpoint"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
    # Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), hence a copy of
    # SourceVm - a VM with a guest OS and PV drivers - rather than an OS-less template clone.
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm.opaque_ref
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref

    $checkpoint = $vm | Invoke-XenVM -XenAction Checkpoint -NewName "sdk-example-checkpoint-1" -PassThru
    Write-Host "Created checkpoint: $($checkpoint.uuid)"
    Write-Host "is_a_snapshot = $($checkpoint.is_a_snapshot)"

    $vm | Invoke-XenVM -XenAction Revert -Snapshot $checkpoint
    # A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
    # Revert restores exactly that - so the VM is Suspended here, not Running as it was before the
    # checkpoint, with a suspend_VDI holding the checkpoint's memory image. Resume clears that:
    # destroying a Suspended VM directly (as a bare "if Running: HardShutdown" check would, since the
    # VM is never Running here) leaves that suspend_VDI behind as a storage leak.
    Write-Host "Reverted the VM to the checkpoint; power state now: $((Get-XenVM -Ref $ref).power_state)"
    $vm | Invoke-XenVM -XenAction Resume

    # Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
    Remove-VmAndDisks -Ref $checkpoint.opaque_ref
    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $ref
    Write-Host "OK: checkpoint-vm"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-6e0a-000000000000
is_a_snapshot = True
Reverted the VM to the checkpoint; power state now: Suspended
OK: checkpoint-vm
```

</details>

## xe CLI

Source: [`cli/virtual-machines/checkpoint-vm.sh`](../../cli/virtual-machines/checkpoint-vm.sh)

```bash
# Checkpoint & revert.
#
# Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you would
# before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works on a throwaway
# copy of a VM with a guest OS and PV drivers (source_vm).
#
# Run it:
#   ./workflows.sh checkpoint-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)

# Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), hence a copy of
# source_vm - a VM with a guest OS and PV drivers - rather than an OS-less template clone.
checkpoint_vm() {
    local source_vm=$(param source_vm "web-01")
    vm=$(copy_of_guest "$source_vm" "xe-example-checkpoint")
    xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"
    cp=$(xe vm-checkpoint uuid=$vm new-name-label=xe-example-checkpoint-1)
    echo "Created checkpoint: $cp"
    xe snapshot-revert snapshot-uuid=$cp
    # A checkpoint's own power-state is always Suspended (it captures memory as well as disk), and
    # snapshot-revert restores exactly that - so the VM is Suspended here, not Running as it was before
    # the checkpoint, with a suspend-VDI holding the checkpoint's memory image. vm-resume clears that:
    # destroying a Suspended VM directly leaves that suspend-VDI behind as a storage leak.
    echo "Reverted to the checkpoint; power-state now: $(xe vm-param-get uuid=$vm param-name=power-state)"
    xe vm-resume uuid=$vm
    # Tidy up so the example is repeatable. The checkpoint owns its own snapshot disks (and memory
    # image), separate from the VM's; the -uninstall commands destroy them with the records.
    xe snapshot-uninstall snapshot-uuid=$cp force=true
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    echo "OK: checkpoint-vm"
}
```

<details><summary>Example output</summary>

```text
Created checkpoint: 00000001-0000-0000-600a-000000000000
Reverted to the checkpoint; power-state now: suspended
OK: checkpoint-vm
```

</details>
