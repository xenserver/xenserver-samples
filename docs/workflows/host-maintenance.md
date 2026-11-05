<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Enter & exit maintenance mode

Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running guests to another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and PV drivers (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation something to move.

**Caution:** moves the host's running VMs to other hosts while it is in maintenance mode.

Workflow `host-maintenance`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/HostMaintenance.cs`](../../csharp/HostsAndPools/HostMaintenance.cs)

```csharp
/// <summary>
/// Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running guests to
/// another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and PV drivers
/// (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation something to
/// move.
/// </summary>
/// <example>
/// <code>
/// Workflows.HostMaintenance("https://xenserver", "root", password, "web-01", "Shared NFS");
/// </code>
/// </example>
public static void HostMaintenance(string url, string user, string password,
    string sourceVm, string srName, string newVmName = "sdk-example-maint")
{
    var session = Connect(url, user, password);
    // Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
    var master = Pool.get_all_records(session).Values.First().master.opaque_ref;
    var hostRef = Host.get_all_records(session).Keys.First(h => h.opaque_ref != master).opaque_ref;
    Console.WriteLine($"Maintenance host: {Host.get_name_label(session, hostRef)}");

    // Pin a throwaway copy of sourceVm to that host so evacuation has something to move.
    // Evacuation live-migrates the guest, which needs its cooperation (VM_LACKS_FEATURE without PV
    // drivers), so sourceVm must have a guest OS with PV drivers. Evacuation also needs somewhere
    // else in the pool that can actually see the VM's disk - a VM whose only disk is on local
    // (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a pool's installation-time
    // default SR is commonly local storage, so put the pinned VM's disk on a shared SR explicitly.
    var vm = CopyOfGuest(session, sourceVm, newVmName);
    MoveDisksToSr(session, vm, SrByName(session, srName, shared: true));
    VM.set_affinity(session, vm, hostRef);
    VM.start(session, vm, false, true);
    WaitForGuestAgent(session, vm);
    Console.WriteLine($"Guest resident on:{Host.get_name_label(session, VM.get_resident_on(session, vm).opaque_ref)}");

    // Enter maintenance mode: disable the host, then evacuate its guests.
    Host.disable(session, hostRef);
    Console.WriteLine($"After disable:    host.enabled = {Host.get_enabled(session, hostRef)}");
    Host.evacuate(session, hostRef);
    Console.WriteLine($"After evacuate:   guest now on {Host.get_name_label(session, VM.get_resident_on(session, vm).opaque_ref)}");

    // Exit maintenance mode.
    Host.enable(session, hostRef);
    Console.WriteLine($"After enable:     host.enabled = {Host.get_enabled(session, hostRef)}");

    // Tidy up so the example is repeatable.
    VM.hard_shutdown(session, vm);
    DestroyVmAndDisks(session, vm);
    Console.WriteLine("OK: host-maintenance");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Maintenance host: sdk-host2
Guest resident on:sdk-host2
After disable:    host.enabled = False
After evacuate:   guest now on sdk-host1
After enable:     host.enabled = True
OK: host-maintenance
```

</details>

## Python

Source: [`python/hosts_and_pools/host_maintenance.py`](../../python/hosts_and_pools/host_maintenance.py)

```python
"""Enter & exit maintenance mode.

Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running guests
to another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and PV
drivers (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation
something to move.

Run it::

    host_maintenance("https://xenserver", "root", password, "web-01", "Shared NFS")
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, move_disks_to_sr, sr_by_name, wait_for_guest_agent


def host_maintenance(url, username, password, source_vm, sr_name, new_vm_name="sdk-example-maint"):
    """Disable a host, evacuate its running guests to another host, then re-enable it. Pins a
    throwaway copy of source_vm to the host so evacuation has work to do. Evacuation live-migrates
    the guest, which needs its cooperation (VM_LACKS_FEATURE without PV drivers), so source_vm must
    have a guest OS with PV drivers.

    Evacuation needs somewhere else in the pool that can actually see the VM's disk - a VM whose
    only disk is on local (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a
    pool's installation-time default SR is commonly local storage. Put the pinned VM's disk on a
    shared SR explicitly rather than trusting whatever the pool default happens to be."""
    session = connect(url, username, password)
    # Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
    master = list(session.xenapi.pool.get_all_records().values())[0]["master"]
    host_ref = next(ref for ref in session.xenapi.host.get_all_records() if ref != master)
    print("Maintenance host: %s" % session.xenapi.host.get_name_label(host_ref))

    # Pin a running VM to that host so evacuation has something to move.
    vm = copy_of_guest(session, source_vm, new_vm_name)
    move_disks_to_sr(session, vm, sr_by_name(session, sr_name, shared=True))
    session.xenapi.VM.set_affinity(vm, host_ref)
    session.xenapi.VM.start(vm, False, True)
    wait_for_guest_agent(session, vm)
    print("Guest resident on:%s" % session.xenapi.host.get_name_label(session.xenapi.VM.get_resident_on(vm)))

    # Enter maintenance mode: disable the host, then evacuate its guests.
    session.xenapi.host.disable(host_ref)
    print("After disable:    host.enabled = %s" % session.xenapi.host.get_enabled(host_ref))
    session.xenapi.host.evacuate(host_ref)
    print("After evacuate:   guest now on %s"
          % session.xenapi.host.get_name_label(session.xenapi.VM.get_resident_on(vm)))

    # Exit maintenance mode.
    session.xenapi.host.enable(host_ref)
    print("After enable:     host.enabled = %s" % session.xenapi.host.get_enabled(host_ref))

    # Tidy up so the example is repeatable.
    session.xenapi.VM.hard_shutdown(vm)
    destroy_vm_and_disks(session, vm)
    print("OK: host-maintenance")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Maintenance host: sdk-host2
Guest resident on:sdk-host2
After disable:    host.enabled = False
After evacuate:   guest now on sdk-host1
After enable:     host.enabled = True
OK: host-maintenance
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/HostMaintenance.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/HostMaintenance.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.moveDisksToSr;
import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class HostMaintenance {
    private HostMaintenance() {
    }

    /**
     * Enter &amp; exit maintenance mode.
     *
     * <p>Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running
     * guests to another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and
     * PV drivers (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation
     * something to move.
     *
     * <p>Pins a throwaway copy of sourceVm to the host so evacuation has work to do. Evacuation
     * live-migrates the guest, which needs its cooperation (VM_LACKS_FEATURE without PV drivers), so
     * sourceVm must have a guest OS with PV drivers.
     *
     * <p>Evacuation needs somewhere else in the pool that can actually see the VM's disk - a VM whose only
     * disk is on local (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a pool's
     * installation-time default SR is commonly local storage. Put the pinned VM's disk on a shared SR
     * explicitly rather than trusting whatever the pool default happens to be.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * HostMaintenance.run("https://xenserver", "root", password, "web-01", "Shared NFS", "sdk-example-maint");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String sourceVm, String srName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        // Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
        Host master = Pool.getAllRecords(conn).values().iterator().next().master;
        Host hostRef = null;
        for (Host h : Host.getAllRecords(conn).keySet())
            if (!h.equals(master)) { hostRef = h; break; }
        System.out.println("Maintenance host: " + hostRef.getNameLabel(conn));

        // Pin a running VM to that host so evacuation has something to move.
        VM vm = copyOfGuest(conn, sourceVm, newVmName);
        moveDisksToSr(conn, vm, srByName(conn, srName, true));
        vm.setAffinity(conn, hostRef);
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);
        System.out.println("Guest resident on:" + vm.getResidentOn(conn).getNameLabel(conn));

        // Enter maintenance mode: disable the host, then evacuate its guests.
        hostRef.disable(conn);
        System.out.println("After disable:    host.enabled = " + hostRef.getEnabled(conn));
        hostRef.evacuate(conn);
        System.out.println("After evacuate:   guest now on " + vm.getResidentOn(conn).getNameLabel(conn));

        // Exit maintenance mode.
        hostRef.enable(conn);
        System.out.println("After enable:     host.enabled = " + hostRef.getEnabled(conn));

        // Tidy up so the example is repeatable.
        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: host-maintenance");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Maintenance host: sdk-host2
Guest resident on:sdk-host2
After disable:    host.enabled = false
After evacuate:   guest now on sdk-host1
After enable:     host.enabled = true
OK: host-maintenance
```

</details>

## Go

Source: [`go/host_maintenance.go`](../../go/host_maintenance.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// hostMaintenance disables a host, evacuates its running guests to another host, then re-enables
// it. Pins a throwaway copy of sourceVM to the host so evacuation has work to do. Evacuation
// live-migrates the guest, which needs its cooperation (VM_LACKS_FEATURE without PV drivers), so
// sourceVM must have a guest OS with PV drivers.
//
// Run it:
//
//	hostMaintenance("https://xenserver", "root", password, "web-01", "Shared NFS", "sdk-example-maint")
func hostMaintenance(url, user, password, sourceVM, srName, newVMName string) {
	session := connect(url, user, password)
	// Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
	pools, err := xenapi.Pool.GetAllRecords(session)
	check(err)
	var master xenapi.HostRef
	for _, p := range pools {
		master = p.Master
		break
	}
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var hostRef xenapi.HostRef
	for ref := range hosts {
		if ref != master {
			hostRef = ref
			break
		}
	}
	hostName, _ := xenapi.Host.GetNameLabel(session, hostRef)
	fmt.Printf("Maintenance host: %s\n", hostName)

	// Pin a running VM to that host so evacuation has something to move.
	vm := copyOfGuest(session, sourceVM, newVMName)
	// Evacuation needs somewhere else in the pool that can actually see the VM's disk - a VM whose
	// only disk is on local (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a
	// pool's installation-time default SR is commonly local storage. Put the pinned VM's disk on a
	// shared SR explicitly rather than trusting whatever the pool default happens to be.
	moveDisksToSR(session, vm, srByName(session, srName, true))
	check(xenapi.VM.SetAffinity(session, vm, hostRef))
	check(xenapi.VM.Start(session, vm, false, true))
	waitForGuestAgent(session, vm)
	on, _ := xenapi.VM.GetResidentOn(session, vm)
	onName, _ := xenapi.Host.GetNameLabel(session, on)
	fmt.Printf("Guest resident on:%s\n", onName)

	// Enter maintenance mode: disable the host, then evacuate its guests.
	check(xenapi.Host.Disable(session, hostRef, true))
	enabled, _ := xenapi.Host.GetEnabled(session, hostRef)
	fmt.Printf("After disable:    host.enabled = %v\n", enabled)
	check(xenapi.Host.Evacuate2(session, hostRef))
	moved, _ := xenapi.VM.GetResidentOn(session, vm)
	movedName, _ := xenapi.Host.GetNameLabel(session, moved)
	fmt.Printf("After evacuate:   guest now on %s\n", movedName)

	// Exit maintenance mode.
	check(xenapi.Host.Enable(session, hostRef))
	enabled, _ = xenapi.Host.GetEnabled(session, hostRef)
	fmt.Printf("After enable:     host.enabled = %v\n", enabled)

	// Tidy up so the example is repeatable.
	check(xenapi.VM.HardShutdown(session, vm))
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: host-maintenance")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Maintenance host: sdk-host2
Guest resident on:sdk-host2
After disable:    host.enabled = false
After evacuate:   guest now on sdk-host1
After enable:     host.enabled = true
OK: host-maintenance
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-HostMaintenance.ps1`](../../powershell/HostsAndPools/Invoke-HostMaintenance.ps1)

```powershell
function Invoke-HostMaintenance {
    <#
    .SYNOPSIS
        Enter & exit maintenance mode.
    .DESCRIPTION
        Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running guests
        to another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and PV
        drivers (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation
        something to move.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [Parameter(Mandatory = $true)][string]$SrName,
        [string]$NewVmName = "sdk-example-maint"
    )
    # Evacuation needs somewhere else in the pool that can actually see the VM's disk - a VM whose only
    # disk is on local (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a pool's
    # installation-time default SR is commonly local storage. Put the pinned VM's disk on a shared SR
    # explicitly rather than trusting whatever the pool default happens to be. Evacuation also
    # live-migrates the guest, which needs its cooperation (VM_LACKS_FEATURE without PV drivers), so
    # SourceVm must have a guest OS with PV drivers.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
    $masterRef = (Get-XenPool | Select-Object -First 1).master.opaque_ref
    $xenHost = Get-XenHost | Where-Object { $_.opaque_ref -ne $masterRef } | Select-Object -First 1
    Write-Host "Maintenance host: $($xenHost.name_label)"

    # Pin a running VM to that host so evacuation has something to move.
    $sr = Get-XenSR -Name $SrName | Where-Object { $_.shared } | Select-Object -First 1
    if (-not $sr) { throw "No shared SR named '$SrName' was found." }
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm.opaque_ref
    Move-DisksToSr -VmRef $ref -SrRef $sr.opaque_ref
    $vm | Set-XenVM -Affinity $xenHost
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref
    Write-Host "Guest resident on:$((Get-XenHost -Ref (Get-XenVM -Ref $ref).resident_on).name_label)"

    # Enter maintenance mode: disable the host, then evacuate its guests.
    $xenHost | Invoke-XenHost -XenAction Disable
    Write-Host "After disable:    host.enabled = $((Get-XenHost -Ref $xenHost.opaque_ref).enabled)"
    Invoke-Evacuate -XenHost $xenHost
    Write-Host "After evacuate:   guest now on $((Get-XenHost -Ref (Get-XenVM -Ref $ref).resident_on).name_label)"

    # Exit maintenance mode.
    $xenHost | Invoke-XenHost -XenAction Enable
    Write-Host "After enable:     host.enabled = $((Get-XenHost -Ref $xenHost.opaque_ref).enabled)"

    # Tidy up so the example is repeatable.
    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "OK: host-maintenance"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Maintenance host: sdk-host2
Guest resident on:sdk-host2
After disable:    host.enabled = False
After evacuate:   guest now on sdk-host1
After enable:     host.enabled = True
OK: host-maintenance
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/host-maintenance.sh`](../../cli/hosts-and-pools/host-maintenance.sh)

```bash
# Enter & exit maintenance mode.
#
# Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running guests to
# another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and PV drivers
# (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation something to move.
#
# Run it:
#   ./workflows.sh host-maintenance https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)
#   sr_name (Shared NFS)

# Pins a throwaway copy of source_vm to a host (not the coordinator, so the coordinator can receive its
# evacuated guests) so evacuation has work to do. Evacuation live-migrates the guest, which needs its
# cooperation (VM_LACKS_FEATURE without PV drivers), so source_vm must have a guest OS with PV drivers.
#
# Evacuation also needs somewhere else in the pool that can actually see the VM's disk - a VM whose only
# disk is on local (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a pool's
# installation-time default SR is commonly local storage. Move the pinned VM's disk onto a shared SR
# (sr_name, below) explicitly rather than trusting whatever the pool default happens to be.
host_maintenance() {
    local source_vm sr_name
    source_vm=$(param source_vm "web-01")
    sr_name=$(param sr_name "Shared NFS")

    # Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
    master=$(xe pool-param-get uuid=$(first_csv "$(xe pool-list --minimal)") param-name=master)
    h=""
    for candidate in $(each_csv "$(xe host-list --minimal)"); do
        [ "$candidate" != "$master" ] && { h=$candidate; break; }
    done
    echo "Maintenance host: $(xe host-param-get uuid=$h param-name=name-label)"

    # Pin a copy of source_vm to that host so evacuation has something to move.
    vm=$(copy_of_guest "$source_vm" "xe-example-maint")
    move_disks_to_sr "$vm" "$(first_csv "$(xe sr-list name-label="$sr_name" shared=true --minimal)")"
    xe vm-param-set uuid=$vm affinity=$h
    xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"
    echo "Guest resident on:$(xe host-param-get uuid=$(xe vm-param-get uuid=$vm param-name=resident-on) param-name=name-label)"

    # Enter maintenance mode: disable the host, then evacuate its guests.
    xe host-disable uuid=$h;  echo "After disable:  enabled=$(xe host-param-get uuid=$h param-name=enabled)"
    xe host-evacuate uuid=$h; echo "After evacuate: guest now on $(xe host-param-get uuid=$(xe vm-param-get uuid=$vm param-name=resident-on) param-name=name-label)"
    xe host-enable uuid=$h;   echo "After enable:   enabled=$(xe host-param-get uuid=$h param-name=enabled)"
    # Tidy up so the example is repeatable: stop the VM, then vm-uninstall destroys it and the disks it
    # owns (vm-destroy would leave the disks behind).
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    echo "OK: host-maintenance"
}
```

<details><summary>Example output</summary>

```text
Maintenance host: sdk-host2
Guest resident on:sdk-host2
After disable:  enabled=false
After evacuate: guest now on sdk-host1
After enable:   enabled=true
OK: host-maintenance
```

</details>
