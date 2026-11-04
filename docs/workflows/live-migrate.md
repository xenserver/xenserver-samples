<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Live migrate a VM

Move a running VM to another host in the pool with no downtime: check the destination can boot it, live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm), with its disks moved first to a shared storage repository (sr_name) so the destination host can see them.

Workflow `live-migrate`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Migration/LiveMigrate.cs`](../../csharp/Migration/LiveMigrate.cs)

```csharp
/// <summary>
/// Move a running VM to another host in the pool with no downtime: check the destination can boot it,
/// live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and PV
/// drivers (source_vm), with its disks moved first to a shared storage repository (sr_name) so the
/// destination host can see them.
/// </summary>
/// <example>
/// <code>
/// Workflows.LiveMigrate("https://xenserver", "root", password, "web-01", "Shared NFS");
/// </code>
/// </example>
public static void LiveMigrate(string url, string user, string password,
    string sourceVm, string srName, string newVmName = "sdk-example-migrate")
{
    var session = Connect(url, user, password);
    // Moves a throwaway copy of sourceVm, a VM with a guest OS and PV drivers: live migration
    // needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers). Only the VM's memory
    // moves, so the destination host has to see its disks already: a disk on local storage
    // refuses with VM_REQUIRES_SR. Put the copy's disks on the shared SR srName first.
    var vm = CopyOfGuest(session, sourceVm, newVmName);
    MoveDisksToSr(session, vm, SrByName(session, srName, shared: true));
    VM.start(session, vm, false, true);
    WaitForGuestAgent(session, vm);

    var sourceHost = VM.get_resident_on(session, vm).opaque_ref;
    Console.WriteLine($"VM is running on: {Host.get_name_label(session, sourceHost)}");

    // Pick a different host in the pool to receive the VM.
    var destHost = Host.get_all_records(session).Keys.First(h => h.opaque_ref != sourceHost).opaque_ref;

    // Check the destination can boot it, then live-migrate (empty options = default live migration).
    VM.assert_can_boot_here(session, vm, destHost);
    VM.pool_migrate(session, vm, destHost, new Dictionary<string, string>());

    Console.WriteLine($"Migrated to:      {Host.get_name_label(session, VM.get_resident_on(session, vm).opaque_ref)}");
    Console.WriteLine($"Still running:    {VM.get_power_state(session, vm)}");

    // Tidy up so the example is repeatable.
    VM.hard_shutdown(session, vm);
    DestroyVmAndDisks(session, vm);
    Console.WriteLine("OK: live-migrate");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
VM is running on: sdk-host1
Migrated to:      sdk-host2
Still running:    Running
OK: live-migrate
```

</details>

## Python

Source: [`python/migration/live_migrate.py`](../../python/migration/live_migrate.py)

```python
"""Live migrate a VM.

Move a running VM to another host in the pool with no downtime: check the destination can boot it,
live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and PV
drivers (source_vm), with its disks moved first to a shared storage repository (sr_name) so the
destination host can see them.

Run it::

    live_migrate("https://xenserver", "root", password, "web-01", "Shared NFS")
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, move_disks_to_sr, sr_by_name, wait_for_guest_agent


def live_migrate(url, username, password, source_vm, sr_name, new_vm_name="sdk-example-migrate"):
    """Live-migrate a running VM to another host in the pool, with no downtime. Moves a throwaway
    copy of source_vm, a VM with a guest OS and PV drivers: live migration needs the guest's
    cooperation (VM_LACKS_FEATURE without PV drivers).

    Only the VM's memory moves, so the destination host has to see its disks already: a disk on
    local storage refuses with VM_REQUIRES_SR. Put the copy's disks on the shared SR sr_name first."""
    session = connect(url, username, password)
    vm = copy_of_guest(session, source_vm, new_vm_name)
    move_disks_to_sr(session, vm, sr_by_name(session, sr_name, shared=True))
    session.xenapi.VM.start(vm, False, True)
    wait_for_guest_agent(session, vm)

    source_host = session.xenapi.VM.get_resident_on(vm)
    print("VM is running on: %s" % session.xenapi.host.get_name_label(source_host))

    # Pick a different host in the pool to receive the VM.
    dest_host = next(ref for ref in session.xenapi.host.get_all_records()
                     if ref != source_host)

    # Check the destination can boot it, then live-migrate (empty options = default live migration).
    session.xenapi.VM.assert_can_boot_here(vm, dest_host)
    session.xenapi.VM.pool_migrate(vm, dest_host, {})

    print("Migrated to:      %s" % session.xenapi.host.get_name_label(session.xenapi.VM.get_resident_on(vm)))
    print("Still running:    %s" % session.xenapi.VM.get_power_state(vm))

    # Tidy up so the example is repeatable.
    session.xenapi.VM.hard_shutdown(vm)
    destroy_vm_and_disks(session, vm)
    print("OK: live-migrate")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
VM is running on: sdk-host1
Migrated to:      sdk-host2
Still running:    Running
OK: live-migrate
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/migration/LiveMigrate.java`](../../java/src/main/java/com/xenserver/samples/migration/LiveMigrate.java)

```java
package com.xenserver.samples.migration;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.moveDisksToSr;
import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class LiveMigrate {
    private LiveMigrate() {
    }

    /**
     * Live migrate a VM.
     *
     * <p>Move a running VM to another host in the pool with no downtime: check the destination can boot
     * it, live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and
     * PV drivers (source_vm), with its disks moved first to a shared storage repository (sr_name) so the
     * destination host can see them.
     *
     * <p>Moves a throwaway copy of sourceVm, a VM with a guest OS and PV drivers: live migration needs the
     * guest's cooperation (VM_LACKS_FEATURE without PV drivers). Only the VM's memory moves, so the
     * destination host has to see its disks already: a disk on local storage refuses with VM_REQUIRES_SR.
     * Put the copy's disks on the shared SR srName first.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * LiveMigrate.run("https://xenserver", "root", password, "web-01", "Shared NFS", "sdk-example-migrate");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String sourceVm, String srName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = copyOfGuest(conn, sourceVm, newVmName);
        moveDisksToSr(conn, vm, srByName(conn, srName, true));
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);

        Host sourceHost = vm.getResidentOn(conn);
        System.out.println("VM is running on: " + sourceHost.getNameLabel(conn));

        // Pick a different host in the pool to receive the VM.
        Host destHost = null;
        for (Host h : Host.getAllRecords(conn).keySet())
            if (!h.equals(sourceHost)) { destHost = h; break; }

        // Check the destination can boot it, then live-migrate (empty options = default live migration).
        vm.assertCanBootHere(conn, destHost);
        vm.poolMigrate(conn, destHost, new java.util.HashMap<>());

        System.out.println("Migrated to:      " + vm.getResidentOn(conn).getNameLabel(conn));
        System.out.println("Still running:    " + vm.getPowerState(conn));

        // Tidy up so the example is repeatable.
        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: live-migrate");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
VM is running on: sdk-host1
Migrated to:      sdk-host2
Still running:    Running
OK: live-migrate
```

</details>

## Go

Source: [`go/live_migrate.go`](../../go/live_migrate.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// liveMigrate live-migrates a running VM to another host in the pool, with no downtime. Moves a
// throwaway copy of sourceVM, a VM with a guest OS and PV drivers: live migration needs the
// guest's cooperation (VM_LACKS_FEATURE without PV drivers). Only the VM's memory moves, so the
// destination host has to see its disks already: a disk on local storage refuses with
// VM_REQUIRES_SR. Put the copy's disks on the shared SR srName first.
//
// Run it:
//
//	liveMigrate("https://xenserver", "root", password, "web-01", "Shared NFS", "sdk-example-migrate")
func liveMigrate(url, user, password, sourceVM, srName, newVMName string) {
	session := connect(url, user, password)
	vm := copyOfGuest(session, sourceVM, newVMName)
	moveDisksToSR(session, vm, srByName(session, srName, true))
	check(xenapi.VM.Start(session, vm, false, true))
	waitForGuestAgent(session, vm)

	sourceHost, err := xenapi.VM.GetResidentOn(session, vm)
	check(err)
	srcName, _ := xenapi.Host.GetNameLabel(session, sourceHost)
	fmt.Printf("VM is running on: %s\n", srcName)

	// Pick a different host in the pool to receive the VM.
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var destHost xenapi.HostRef
	for ref := range hosts {
		if ref != sourceHost {
			destHost = ref
			break
		}
	}

	// Check the destination can boot it, then live-migrate (empty options = default live migration).
	check(xenapi.VM.AssertCanBootHere(session, vm, destHost))
	check(xenapi.VM.PoolMigrate(session, vm, destHost, map[string]string{}))

	nowHost, _ := xenapi.VM.GetResidentOn(session, vm)
	nowName, _ := xenapi.Host.GetNameLabel(session, nowHost)
	ps, _ := xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Migrated to:      %s\n", nowName)
	fmt.Printf("Still running:    %s\n", ps)

	// Tidy up so the example is repeatable.
	check(xenapi.VM.HardShutdown(session, vm))
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: live-migrate")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
VM is running on: sdk-host1
Migrated to:      sdk-host2
Still running:    Running
OK: live-migrate
```

</details>

## PowerShell

Source: [`powershell/Migration/Invoke-LiveMigrate.ps1`](../../powershell/Migration/Invoke-LiveMigrate.ps1)

```powershell
function Invoke-LiveMigrate {
    <#
    .SYNOPSIS
        Live migrate a VM.
    .DESCRIPTION
        Move a running VM to another host in the pool with no downtime: check the destination can boot it,
        live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and PV
        drivers (source_vm), with its disks moved first to a shared storage repository (sr_name) so the
        destination host can see them.
    .EXAMPLE
        Invoke-LiveMigrate -Url https://xenserver -UserName root -Password $password -SourceVm 'web-01' -SrName 'Shared NFS'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [Parameter(Mandatory = $true)][string]$SrName,
        [string]$NewVmName = "sdk-example-migrate"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Live migration needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so this moves a
    # throwaway copy of SourceVm, a VM with a guest OS and PV drivers. Only the VM's memory moves, so the
    # destination host has to see its disks already: a disk on local storage refuses with VM_REQUIRES_SR.
    # Put the copy's disks on the shared SR SrName first.
    $sr = Get-XenSR -Name $SrName | Where-Object { $_.shared } | Select-Object -First 1
    if (-not $sr) { throw "No shared SR named '$SrName' was found." }
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm.opaque_ref
    Move-DisksToSr -VmRef $ref -SrRef $sr.opaque_ref
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref

    $sourceHostRef = (Get-XenVM -Ref $ref).resident_on.opaque_ref
    Write-Host "VM is running on: $((Get-XenHost -Ref $sourceHostRef).name_label)"

    # Pick a different host in the pool to receive the VM.
    $destHost = Get-XenHost | Where-Object { $_.opaque_ref -ne $sourceHostRef } | Select-Object -First 1

    # Check the destination can boot it, then live-migrate. Both are native cmdlet actions: the
    # destination host is passed as -XenHost and the (empty) options map as -Options.
    $vm | Invoke-XenVM -XenAction AssertCanBootHere -XenHost $destHost
    $vm | Invoke-XenVM -XenAction PoolMigrate -XenHost $destHost -Options @{}  # @{} = default live migration

    Write-Host "Migrated to:      $((Get-XenHost -Ref (Get-XenVM -Ref $ref).resident_on).name_label)"
    Write-Host "Still running:    $((Get-XenVM -Ref $ref).power_state)"

    # Tidy up so the example is repeatable.
    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "OK: live-migrate"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
VM is running on: sdk-host1
Migrated to:      sdk-host2
Still running:    Running
OK: live-migrate
```

</details>

## xe CLI

Source: [`cli/migration/live-migrate.sh`](../../cli/migration/live-migrate.sh)

```bash
# Live migrate a VM.
#
# Move a running VM to another host in the pool with no downtime: check the destination can boot it,
# live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and PV drivers
# (source_vm), with its disks moved first to a shared storage repository (sr_name) so the destination host can
# see them.
#
# Run it:
#   ./workflows.sh live-migrate https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)
#   sr_name (Shared NFS)

# Live migration needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so this moves a
# throwaway copy of source_vm, a VM with a guest OS and PV drivers. Only the VM's memory moves, so the
# destination host has to see its disks already: a disk on local storage refuses with VM_REQUIRES_SR.
# Put the copy's disks on the shared SR sr_name first.
live_migrate() {
    local source_vm sr_name
    source_vm=$(param source_vm "web-01")
    sr_name=$(param sr_name "Shared NFS")
    vm=$(copy_of_guest "$source_vm" "xe-example-migrate")
    move_disks_to_sr "$vm" "$(first_csv "$(xe sr-list name-label="$sr_name" shared=true --minimal)")"
    xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"
    source=$(xe vm-param-get uuid=$vm param-name=resident-on)
    echo "Running on: $(xe host-param-get uuid=$source param-name=name-label)"
    hosts=$(xe host-list --minimal); dest=""
    for h in ${hosts//,/ }; do [ "$h" != "$source" ] && { dest=$h; break; }; done
    xe vm-migrate uuid=$vm host-uuid=$dest live=true
    now=$(xe vm-param-get uuid=$vm param-name=resident-on)
    echo "Migrated to: $(xe host-param-get uuid=$now param-name=name-label)"
    # Tidy up so the example is repeatable: stop the VM, then vm-uninstall destroys it and the disks it
    # owns (vm-destroy would leave the disks behind).
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    echo "OK: live-migrate"
}
```

<details><summary>Sample output</summary>

```text
Running on: sdk-host1
Migrated to: sdk-host2
OK: live-migrate
```

</details>
