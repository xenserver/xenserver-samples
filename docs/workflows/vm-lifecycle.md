<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# VM power lifecycle

Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down cleanly. Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy of a VM with a guest OS and PV drivers (source_vm), which is deleted again with its disks afterwards.

Workflow `vm-lifecycle`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-VmLifecycle.ps1`](../../powershell/VirtualMachines/Invoke-VmLifecycle.ps1)

```powershell
function Invoke-VmLifecycle {
    <#
    .SYNOPSIS
        VM power lifecycle.
    .DESCRIPTION
        Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down
        cleanly. Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy
        of a VM with a guest OS and PV drivers (source_vm), which is deleted again with its disks
        afterwards.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [string]$NewVmName = "sdk-example-lifecycle"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so
    # the copy is made from SourceVm, a VM with a guest OS and PV drivers, and the example waits for the
    # guest to report in after starting. Suspend also needs a suspend-image SR (the VM's own, else the
    # pool's, else the host's); check one is actually configured before trying.
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm.opaque_ref

    function State { (Get-XenVM -Ref $ref).power_state }

    Write-Host "Initial power state: $(State)"

    # Start asynchronously: -Async -PassThru emits a Task, which pipes straight into Wait-XenTask.
    # -ShowProgress surfaces the task's progress - the idiom for long-running operations where you want
    # to track progress rather than block silently.
    $vm | Invoke-XenVM -XenAction Start -Async -PassThru | Wait-XenTask -ShowProgress
    Wait-GuestAgent -Ref $ref
    Write-Host "After start:    $(State)"

    # The emulated hardware (the device model) can be restarted under a running guest without rebooting
    # it - what you reach for when the VM's virtual devices misbehave.
    $vm | Invoke-XenVM -XenAction RestartDeviceModels
    Write-Host "Device models restarted; still $(State)"

    # VM.suspend needs a suspend-image SR actually configured (the VM's own, else the pool's, else the
    # resident host's - the same fallback order xapi's choose_suspend_sr uses) - VM_NO_SUSPEND_SR
    # otherwise. Check before trying rather than assuming one is set.
    if (Test-HasSuspendSr -Vm (Get-XenVM -Ref $ref)) {
        $vm | Invoke-XenVM -XenAction Suspend
        Write-Host "After suspend:  $(State)"
        $vm | Invoke-XenVM -XenAction Resume
        Wait-GuestAgent -Ref $ref   # the PV drivers reconnect after a resume
        Write-Host "After resume:   $(State)"
    }
    else {
        Write-Host "Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host"
    }

    # A clean shutdown asks the guest OS to shut itself down, as pressing the power button would.
    $vm | Invoke-XenVM -XenAction CleanShutdown
    Write-Host "After shutdown: $(State)"

    Remove-VmAndDisks -Ref $ref
    Write-Host "OK: vm-lifecycle"
    $session | Disconnect-XenServer
}

function Test-HasSuspendSr {
    <#
    .SYNOPSIS
        Whether VM.suspend has a suspend-image SR to use.
    .DESCRIPTION
        The VM's own, else the pool's, else the resident host's - the same fallback order xapi's
        choose_suspend_sr uses.
    #>
    param($Vm)
    if ($Vm.suspend_SR.opaque_ref -ne 'OpaqueRef:NULL') { return $true }
    $pool = Get-XenPool | Select-Object -First 1
    if ($pool.suspend_image_SR.opaque_ref -ne 'OpaqueRef:NULL') { return $true }
    return (Get-XenHost -Ref $pool.master.opaque_ref).suspend_image_sr.opaque_ref -ne 'OpaqueRef:NULL'
}
```

<details><summary>Example output</summary>

```text
Initial power state: Halted
After start:    Running
Device models restarted; still Running
After suspend:  Suspended
After resume:   Running
After shutdown: Halted
OK: vm-lifecycle
```

</details>

## xe CLI

Source: [`cli/virtual-machines/vm-lifecycle.sh`](../../cli/virtual-machines/vm-lifecycle.sh)

```bash
# VM power lifecycle.
#
# Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down cleanly.
# Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy of a VM with a
# guest OS and PV drivers (source_vm), which is deleted again with its disks afterwards.
#
# Run it:
#   ./workflows.sh vm-lifecycle https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)

vm_lifecycle() {
    local source_vm=$(param source_vm "web-01")
    # Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so
    # the copy is made from source_vm, a VM with a guest OS and PV drivers, and the example waits for the
    # guest to report in after starting.
    vm=$(copy_of_guest "$source_vm" "xe-example-lifecycle")
    echo "Initial: $(xe vm-param-get uuid=$vm param-name=power-state)"
    xe vm-start uuid=$vm;   echo "After start:    $(xe vm-param-get uuid=$vm param-name=power-state)"
    wait_for_guest_agent "$vm"
    # The emulated hardware can be restarted under a running guest without rebooting it.
    xe vm-restart-device-models uuid=$vm
    echo "Device models restarted; still $(xe vm-param-get uuid=$vm param-name=power-state)"
    if has_suspend_sr "$vm"; then
        xe vm-suspend uuid=$vm; echo "After suspend:  $(xe vm-param-get uuid=$vm param-name=power-state)"
        xe vm-resume uuid=$vm;  echo "After resume:   $(xe vm-param-get uuid=$vm param-name=power-state)"
        wait_for_guest_agent "$vm"   # the PV drivers reconnect after a resume
    else
        echo "Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host"
    fi
    # A clean shutdown asks the guest OS to shut itself down, as pressing the power button would - safe
    # now that the VM is a copy of a guest with PV drivers (an OS-less template clone would hang or fail
    # for real on a real host, with no public fallback to a hard shutdown).
    xe vm-shutdown uuid=$vm; echo "After shutdown: $(xe vm-param-get uuid=$vm param-name=power-state)"
    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it owns (vm-destroy
    # would leave the disks behind).
    xe vm-uninstall uuid=$vm force=true
    echo "OK: vm-lifecycle"
}

# Whether VM.suspend has a suspend-image SR to use: the VM's own, else the pool's, else the resident
# host's - the same fallback order xapi's choose_suspend_sr uses.
has_suspend_sr() {
    local vm=$1 pool host
    [ -n "$(xe vm-param-get uuid=$vm param-name=suspend-SR)" ] && return 0
    pool=$(first_csv "$(xe pool-list --minimal)")
    [ -n "$(xe pool-param-get uuid=$pool param-name=suspend-image-SR)" ] && return 0
    host=$(xe pool-param-get uuid=$pool param-name=master)
    [ -n "$(xe host-param-get uuid=$host param-name=suspend-image-sr)" ]
}
```

<details><summary>Example output</summary>

```text
Initial: halted
After start:    running
Device models restarted; still running
Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host
After shutdown: halted
OK: vm-lifecycle
```

</details>

## Python

Source: [`python/virtual_machines/vm_lifecycle.py`](../../python/virtual_machines/vm_lifecycle.py)

```python
"""VM power lifecycle.

Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down
cleanly. Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy
of a VM with a guest OS and PV drivers (source_vm), which is deleted again with its disks
afterwards.
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, wait_for_guest_agent


def vm_lifecycle(url, username, password, source_vm, new_vm_name="sdk-example-lifecycle"):
    """Take a throwaway copy of a VM with a guest OS through start -> suspend -> resume -> clean
    shutdown, and delete it again.

    Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
    so the copy is made from source_vm, a VM with a guest OS and PV drivers, and the example waits
    for the guest to report in after starting. Suspend also needs a suspend-image SR (the VM's own,
    else the pool's, else the host's); check one is actually configured before trying."""
    session = connect(url, username, password)
    vm_ref = copy_of_guest(session, source_vm, new_vm_name)

    def state():
        return session.xenapi.VM.get_power_state(vm_ref)

    print("Initial power state: %s" % state())
    session.xenapi.VM.start(vm_ref, False, True)
    wait_for_guest_agent(session, vm_ref)
    print("After start:   %s" % state())

    # The emulated hardware (the device model) can be restarted under a running guest without
    # rebooting it -- what you reach for when the VM's virtual devices misbehave.
    session.xenapi.VM.restart_device_models(vm_ref)
    print("Device models restarted; still %s" % state())

    if _has_suspend_sr(session, vm_ref):
        session.xenapi.VM.suspend(vm_ref)
        print("After suspend: %s" % state())
        session.xenapi.VM.resume(vm_ref, False, True)
        wait_for_guest_agent(session, vm_ref)   # the PV drivers reconnect after a resume
        print("After resume:  %s" % state())
    else:
        print("Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host")

    # A clean shutdown asks the guest OS to shut itself down, as pressing the power button would.
    session.xenapi.VM.clean_shutdown(vm_ref)
    print("After shutdown:%s" % state())

    destroy_vm_and_disks(session, vm_ref)
    print("OK: vm-lifecycle")
    session.xenapi.session.logout()


def _has_suspend_sr(session, vm):
    """Whether VM.suspend has a suspend-image SR to use: the VM's own, else the pool's, else the
    resident host's - the same fallback order xapi's choose_suspend_sr uses."""
    x = session.xenapi
    if x.VM.get_suspend_SR(vm) != "OpaqueRef:NULL":
        return True
    pool = x.pool.get_all()[0]
    if x.pool.get_suspend_image_SR(pool) != "OpaqueRef:NULL":
        return True
    host = x.pool.get_master(pool)
    return x.host.get_suspend_image_sr(host) != "OpaqueRef:NULL"
```

<details><summary>Example output</summary>

```text
Initial power state: Halted
After start:   Running
Device models restarted; still Running
After suspend: Suspended
After resume:  Running
After shutdown:Halted
OK: vm-lifecycle
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/VmLifecycle.cs`](../../csharp/VirtualMachines/VmLifecycle.cs)

```csharp
/// <summary>
/// Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down
/// cleanly. Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy of
/// a VM with a guest OS and PV drivers (source_vm), which is deleted again with its disks afterwards.
/// </summary>
/// <example>
/// <code>
/// Workflows.VmLifecycle("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void VmLifecycle(string url, string user, string password,
    string sourceVm, string newVmName = "sdk-example-lifecycle")
{
    var session = Connect(url, user, password);
    // Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV
    // drivers), so the copy is made from sourceVm, a VM with a guest OS and PV drivers, and the
    // example waits for the guest to report in after starting. Suspend also needs a suspend-image
    // SR (the VM's own, else the pool's, else the host's); check one is actually configured before
    // trying.
    var vmRef = CopyOfGuest(session, sourceVm, newVmName);

    string State() => VM.get_power_state(session, vmRef).ToString();

    Console.WriteLine($"Initial power state: {State()}");
    VM.start(session, vmRef, false, true);
    WaitForGuestAgent(session, vmRef);
    Console.WriteLine($"After start:    {State()}");

    // The emulated hardware (the device model) can be restarted under a running guest without
    // rebooting it — what you reach for when the VM's virtual devices misbehave.
    VM.restart_device_models(session, vmRef);
    Console.WriteLine($"Device models restarted; still {State()}");

    if (HasSuspendSr(session, vmRef))
    {
        VM.suspend(session, vmRef);
        Console.WriteLine($"After suspend:  {State()}");
        VM.resume(session, vmRef, false, true);
        WaitForGuestAgent(session, vmRef); // the PV drivers reconnect after a resume
        Console.WriteLine($"After resume:   {State()}");
    }
    else
    {
        Console.WriteLine("Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host");
    }

    // A clean shutdown asks the guest OS to shut itself down, as pressing the power button would.
    VM.clean_shutdown(session, vmRef);
    Console.WriteLine($"After shutdown: {State()}");

    DestroyVmAndDisks(session, vmRef);
    Console.WriteLine("OK: vm-lifecycle");
    session.logout();
}

/// <summary>
/// Whether VM.suspend has a suspend-image SR to use: the VM's own, else the pool's, else the
/// resident host's - the same fallback order xapi's choose_suspend_sr uses.
/// </summary>
private static bool HasSuspendSr(Session session, string vm)
{
    if (VM.get_suspend_SR(session, vm).opaque_ref != "OpaqueRef:NULL") return true;
    var pool = Pool.get_all(session)[0].opaque_ref;
    if (Pool.get_suspend_image_SR(session, pool).opaque_ref != "OpaqueRef:NULL") return true;
    var host = Pool.get_master(session, pool).opaque_ref;
    return Host.get_suspend_image_sr(session, host).opaque_ref != "OpaqueRef:NULL";
}
```

<details><summary>Example output</summary>

```text
Initial power state: Halted
After start:    Running
Device models restarted; still Running
After suspend:  Suspended
After resume:   Running
After shutdown: Halted
OK: vm-lifecycle
```

</details>

## Go

Source: [`go/vm_lifecycle.go`](../../go/vm_lifecycle.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// vmLifecycle takes a throwaway copy of a VM with a guest OS through start -> suspend -> resume ->
// clean shutdown, and deletes it again.
//
// Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
// so the copy is made from sourceVM, a VM with a guest OS and PV drivers, and the example waits
// for the guest to report in after starting. Suspend also needs a suspend-image SR (the VM's own,
// else the pool's, else the host's); check one is actually configured before trying.
func vmLifecycle(url, user, password, sourceVM, newVMName string) {
	session := connect(url, user, password)
	vmRef := copyOfGuest(session, sourceVM, newVMName)

	state := func() xenapi.VMPowerState {
		s, _ := xenapi.VM.GetPowerState(session, vmRef)
		return s
	}

	fmt.Printf("Initial power state: %s\n", state())
	check(xenapi.VM.Start(session, vmRef, false, true))
	waitForGuestAgent(session, vmRef)
	fmt.Printf("After start:    %s\n", state())

	// The emulated hardware (the device model) can be restarted under a running guest without
	// rebooting it - what you reach for when the VM's virtual devices misbehave.
	check(xenapi.VM.RestartDeviceModels(session, vmRef))
	fmt.Printf("Device models restarted; still %s\n", state())

	// Suspend needs a suspend-image SR (the VM's own, else the pool's, else the host's); check
	// one is actually configured before trying, rather than assuming it is (VM_NO_SUSPEND_SR
	// otherwise on a real host).
	if hasSuspendSR(session, vmRef) {
		check(xenapi.VM.Suspend(session, vmRef))
		fmt.Printf("After suspend:  %s\n", state())
		check(xenapi.VM.Resume(session, vmRef, false, true))
		waitForGuestAgent(session, vmRef) // the PV drivers reconnect after a resume
		fmt.Printf("After resume:   %s\n", state())
	} else {
		fmt.Println("Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host")
	}

	// A clean shutdown asks the guest OS to shut itself down, as pressing the power button would -
	// possible here because the copy has a guest OS with PV drivers.
	check(xenapi.VM.CleanShutdown(session, vmRef))
	fmt.Printf("After shutdown: %s\n", state())

	destroyVMAndDisks(session, vmRef)
	fmt.Println("OK: vm-lifecycle")
	session.Logout()
}

// hasSuspendSR reports whether VM.Suspend has a suspend-image SR to use: the VM's own, else the
// pool's, else the resident host's - the same fallback order xapi's choose_suspend_sr uses.
func hasSuspendSR(session *xenapi.Session, vm xenapi.VMRef) bool {
	if sr, err := xenapi.VM.GetSuspendSR(session, vm); err == nil && sr != "" && sr != "OpaqueRef:NULL" {
		return true
	}
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	if sr, err := xenapi.Pool.GetSuspendImageSR(session, pools[0]); err == nil && sr != "" && sr != "OpaqueRef:NULL" {
		return true
	}
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	sr, err := xenapi.Host.GetSuspendImageSr(session, host)
	return err == nil && sr != "" && sr != "OpaqueRef:NULL"
}
```

<details><summary>Example output</summary>

```text
Initial power state: Halted
After start:    Running
Device models restarted; still Running
After suspend:  Suspended
After resume:   Running
After shutdown: Halted
OK: vm-lifecycle
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/VmLifecycle.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/VmLifecycle.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class VmLifecycle {
    private VmLifecycle() {
    }

    /**
     * VM power lifecycle.
     *
     * <p>Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down
     * cleanly. Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy
     * of a VM with a guest OS and PV drivers (source_vm), which is deleted again with its disks
     * afterwards.
     *
     * <p>Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so
     * the copy is made from sourceVm, a VM with a guest OS and PV drivers, and the example waits for the
     * guest to report in after starting. Suspend also needs a suspend-image SR (the VM's own, else the
     * pool's, else the host's); check one is actually configured before trying, rather than assuming it
     * is.
     */
    public static void run(String url, String user, String password,
            String sourceVm, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = copyOfGuest(conn, sourceVm, newVmName);

        System.out.println("Initial power state: " + vm.getPowerState(conn));
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);
        System.out.println("After start:   " + vm.getPowerState(conn));

        // The emulated hardware (the device model) can be restarted under a running guest without
        // rebooting it - what you reach for when the VM's virtual devices misbehave.
        vm.restartDeviceModels(conn);
        System.out.println("Device models restarted; still " + vm.getPowerState(conn));

        if (hasSuspendSr(conn, vm)) {
            vm.suspend(conn);
            System.out.println("After suspend: " + vm.getPowerState(conn));
            vm.resume(conn, false, true);
            waitForGuestAgent(conn, vm);   // the PV drivers reconnect after a resume
            System.out.println("After resume:  " + vm.getPowerState(conn));
        } else {
            System.out.println("Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host");
        }

        // A clean shutdown asks the guest OS to shut itself down, as pressing the power button would.
        vm.cleanShutdown(conn);
        System.out.println("After shutdown:" + vm.getPowerState(conn));

        destroyVmAndDisks(conn, vm);
        System.out.println("OK: vm-lifecycle");
        Session.logout(conn);
    }

    /**
     * Whether VM.suspend has a suspend-image SR to use: the VM's own, else the pool's, else the resident
     * host's - the same fallback order xapi's choose_suspend_sr uses.
     */
    private static boolean hasSuspendSr(Connection conn, VM vm) throws Exception {
        if (!vm.getSuspendSR(conn).toWireString().equals("OpaqueRef:NULL")) return true;
        Pool pool = Pool.getAll(conn).iterator().next();
        if (!pool.getSuspendImageSR(conn).toWireString().equals("OpaqueRef:NULL")) return true;
        Host host = pool.getMaster(conn);
        return !host.getSuspendImageSr(conn).toWireString().equals("OpaqueRef:NULL");
    }
}
```

<details><summary>Example output</summary>

```text
Initial power state: Halted
After start:   Running
Device models restarted; still Running
After suspend: Suspended
After resume:  Running
After shutdown:Halted
OK: vm-lifecycle
```

</details>
