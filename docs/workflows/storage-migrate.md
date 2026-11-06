<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Storage live-migration

Move a running VM's virtual disk to a different storage repository while the VM keeps running — live storage migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).

Workflow `storage-migrate`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Migration/Invoke-StorageMigrate.ps1`](../../powershell/Migration/Invoke-StorageMigrate.ps1)

```powershell
function Invoke-StorageMigrate {
    <#
    .SYNOPSIS
        Storage live-migration.
    .DESCRIPTION
        Move a running VM's virtual disk to a different storage repository while the VM keeps running — live
        storage migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
    .EXAMPLE
        Invoke-StorageMigrate -Url https://xenserver -UserName root -Password $password -SourceVm 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [string]$NewVmName = "sdk-example-storagemigrate"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so
    # this works on a throwaway copy of SourceVm, a VM with a guest OS and PV drivers. (A halted VM's disk
    # moves too, without the guest; what VDI PoolMigrate always needs is a VM to move the disk for - a VDI
    # no VBD points at fails VDI_NEEDS_VM_FOR_MIGRATE.)
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref

    $vdiRef = (Get-XenVM -Ref $ref).VBDs |
        ForEach-Object { Get-XenVBD -Ref $_ } |
        Where-Object { $_.type -eq 'Disk' } |
        ForEach-Object { $_.VDI } |
        Select-Object -First 1
    $sourceSr = (Get-XenVDI -Ref $vdiRef).SR
    Write-Host "Disk is on SR: $((Get-XenSR -Ref $sourceSr).name_label)"

    # Pick a different SR that holds disks and that the VM's host can reach (a currently-attached PBD
    # there).
    $vmHost = (Get-XenVM -Ref $ref).resident_on
    $reachableSrs = @(Get-XenPBD | Where-Object { $_.host -eq $vmHost -and $_.currently_attached } |
        ForEach-Object { $_.SR })
    $destSr = Get-XenSR | Where-Object {
        $sourceSr -ne $_ -and $_.content_type -ne 'iso' -and $_.type -notin @('iso', 'udev') -and
        $reachableSrs -contains $_
    } | Select-Object -First 1

    # PoolMigrate returns the disk's new VDI: the copy on the destination SR replaces the original.
    $vdiRef = Get-XenVDI -Ref $vdiRef | Invoke-XenVDI -XenAction PoolMigrate -SR $destSr -Options @{} -PassThru

    $nowOn = (Get-XenVDI -Ref $vdiRef).SR
    Write-Host "Disk moved to:  $((Get-XenSR -Ref $nowOn).name_label)"

    # Tidy up: the VM and the disks it now owns.
    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $ref
    Write-Host "OK: storage-migrate"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Disk is on SR: Shared NFS
Disk moved to:  iSCSI storage
OK: storage-migrate
```

</details>

## xe CLI

Source: [`cli/migration/storage-migrate.sh`](../../cli/migration/storage-migrate.sh)

```bash
# Storage live-migration.
#
# Move a running VM's virtual disk to a different storage repository while the VM keeps running — live storage
# migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
#
# Run it:
#   ./workflows.sh storage-migrate https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)

# Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so this
# works on a throwaway copy of source_vm, a VM with a guest OS and PV drivers. (A halted VM's disk moves
# too, without the guest; what vdi-pool-migrate always needs is a VM to move the disk for - a VDI no VBD
# points at fails VDI_NEEDS_VM_FOR_MIGRATE.)
storage_migrate() {
    local source_vm=$(param source_vm "web-01")
    vm=$(copy_of_guest "$source_vm" "xe-example-storagemigrate")
    xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"
    vdi=$(first_disk_vdi "$vm")
    source=$(xe vdi-param-get uuid=$vdi param-name=sr-uuid)
    echo "Disk is on SR: $(xe sr-param-get uuid=$source param-name=name-label)"

    # Pick a different SR that holds disks (not ISO) and that the VM's host can reach (an attached PBD there).
    resident=$(xe vm-param-get uuid=$vm param-name=resident-on)
    dest=""
    for sr in $(each_csv "$(xe sr-list --minimal)"); do
        [ "$sr" = "$source" ] && continue
        [ "$(xe sr-param-get uuid=$sr param-name=content-type)" = "iso" ] && continue
        case "$(xe sr-param-get uuid=$sr param-name=type)" in iso|udev) continue ;; esac
        if [ -n "$(xe pbd-list sr-uuid=$sr host-uuid=$resident currently-attached=true --minimal)" ]; then
            dest=$sr; break
        fi
    done
    # vdi-pool-migrate moves the disk in place: the copy on the destination SR replaces the original.
    xe vdi-pool-migrate uuid=$vdi sr-uuid=$dest
    echo "Disk moved to: $(xe sr-param-get uuid=$(xe vdi-param-get uuid=$vdi param-name=sr-uuid) param-name=name-label)"

    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it now owns
    # (vm-destroy would leave the disks behind).
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    echo "OK: storage-migrate"
}
```

<details><summary>Example output</summary>

```text
Disk is on SR: Shared NFS
Disk moved to: iSCSI storage
OK: storage-migrate
```

</details>

## Python

Source: [`python/migration/storage_migrate.py`](../../python/migration/storage_migrate.py)

```python
"""Storage live-migration.

Move a running VM's virtual disk to a different storage repository while the VM keeps running — live
storage migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).

Run it::

    storage_migrate("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, disk_vdis, wait_for_guest_agent


def storage_migrate(url, username, password, source_vm, new_vm_name="sdk-example-storagemigrate"):
    """Relocate a running VM's disk to a different SR without stopping it (live storage migration)
    with VDI.pool_migrate.

    Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
    so this works on a throwaway copy of source_vm, a VM with a guest OS and PV drivers. (A halted
    VM's disk moves too, without the guest; what VDI.pool_migrate always needs is a VM to move the
    disk for - a VDI no VBD points at fails VDI_NEEDS_VM_FOR_MIGRATE.)"""
    session = connect(url, username, password)
    vm = copy_of_guest(session, source_vm, new_vm_name)
    session.xenapi.VM.start(vm, False, True)
    wait_for_guest_agent(session, vm)
    vdi = disk_vdis(session, vm)[0]
    source_sr = session.xenapi.VDI.get_SR(vdi)
    print("Disk is on SR: %s" % session.xenapi.SR.get_name_label(source_sr))

    # Pick a different SR that holds disks and that the VM's host can reach (an attached PBD there).
    host = session.xenapi.VM.get_resident_on(vm)
    dest_sr = next(ref for ref, r in session.xenapi.SR.get_all_records().items()
                   if ref != source_sr and r["content_type"] != "iso" and r["type"] not in ("iso", "udev")
                   and any(session.xenapi.PBD.get_host(pbd) == host
                           and session.xenapi.PBD.get_currently_attached(pbd) for pbd in r["PBDs"]))
    # pool_migrate returns the disk's new VDI: the copy on the destination SR replaces the original.
    vdi = session.xenapi.VDI.pool_migrate(vdi, dest_sr, {})

    now_on = session.xenapi.VDI.get_SR(vdi)
    print("Disk moved to:  %s" % session.xenapi.SR.get_name_label(now_on))

    # Tidy up: the VM and the disks it now owns.
    session.xenapi.VM.hard_shutdown(vm)
    destroy_vm_and_disks(session, vm)
    print("OK: storage-migrate")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Disk is on SR: Shared NFS
Disk moved to:  iSCSI storage
OK: storage-migrate
```

</details>

## C# (.NET)

Source: [`csharp/Migration/StorageMigrate.cs`](../../csharp/Migration/StorageMigrate.cs)

```csharp
/// <summary>
/// Move a running VM's virtual disk to a different storage repository while the VM keeps running — live
/// storage migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
/// </summary>
/// <example>
/// <code>
/// Workflows.StorageMigrate("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void StorageMigrate(string url, string user, string password,
    string sourceVm, string newVmName = "sdk-example-storagemigrate")
{
    var session = Connect(url, user, password);
    // Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV
    // drivers), so this works on a throwaway copy of sourceVm, a VM with a guest OS and PV drivers.
    // (A halted VM's disk moves too, without the guest; what VDI.pool_migrate always needs is a VM
    // to move the disk for - a VDI no VBD points at fails VDI_NEEDS_VM_FOR_MIGRATE.)
    var vm = CopyOfGuest(session, sourceVm, newVmName);
    VM.start(session, vm, false, true);
    WaitForGuestAgent(session, vm);
    var vdi = DiskVdis(session, vm).First();
    var sourceSr = VDI.get_SR(session, vdi);
    Console.WriteLine($"Disk is on SR: {SR.get_name_label(session, sourceSr)}");

    // Pick a different SR that holds disks and that the VM's host can reach (an attached PBD
    // there).
    var host = VM.get_resident_on(session, vm);
    var destSr = SR.get_all_records(session)
        .First(kv => !kv.Key.Equals(sourceSr) && kv.Value.content_type != "iso"
            && kv.Value.type != "iso" && kv.Value.type != "udev"
            && kv.Value.PBDs.Any(pbd => PBD.get_host(session, pbd).Equals(host)
                && PBD.get_currently_attached(session, pbd))).Key;
    // pool_migrate returns the disk's new VDI: the copy on the destination SR replaces the
    // original. Copying a disk takes minutes, so run it as a task (see AwaitTask).
    vdi = new XenRef<VDI>(AwaitTask(session,
        VDI.async_pool_migrate(session, vdi, destSr, new Dictionary<string, string>())));

    var nowOn = VDI.get_SR(session, vdi);
    Console.WriteLine($"Disk moved to:  {SR.get_name_label(session, nowOn)}");

    // Tidy up: the VM and the disks it now owns.
    VM.hard_shutdown(session, vm);
    DestroyVmAndDisks(session, vm);
    Console.WriteLine("OK: storage-migrate");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Disk is on SR: Shared NFS
Disk moved to:  iSCSI storage
OK: storage-migrate
```

</details>

## Go

Source: [`go/storage_migrate.go`](../../go/storage_migrate.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// storageMigrate relocates a running VM's disk to a different SR without stopping it (live
// storage migration) with VDI.PoolMigrate.
//
// Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
// so this works on a throwaway copy of sourceVM, a VM with a guest OS and PV drivers. (A halted
// VM's disk moves too, without the guest; what VDI.PoolMigrate always needs is a VM to move the
// disk for - a VDI no VBD points at fails VDI_NEEDS_VM_FOR_MIGRATE.)
//
// Run it:
//
//	storageMigrate("https://xenserver", "root", password, "web-01", "sdk-example-storagemigrate")
func storageMigrate(url, user, password, sourceVM, newVMName string) {
	session := connect(url, user, password)
	vm := copyOfGuest(session, sourceVM, newVMName)
	check(xenapi.VM.Start(session, vm, false, true))
	waitForGuestAgent(session, vm)
	vdi := diskVdis(session, vm)[0]
	sourceSr, err := xenapi.VDI.GetSR(session, vdi)
	check(err)
	srcSrName, _ := xenapi.SR.GetNameLabel(session, sourceSr)
	fmt.Printf("Disk is on SR: %s\n", srcSrName)

	// Pick a different SR that holds disks and that the VM's host can reach (an attached PBD there).
	host, err := xenapi.VM.GetResidentOn(session, vm)
	check(err)
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var destSr xenapi.SRRef
	found := false
	for ref, sr := range srs {
		if ref == sourceSr || sr.ContentType == "iso" || sr.Type == "iso" || sr.Type == "udev" {
			continue
		}
		for _, pbdRef := range sr.PBDs {
			pbdHost, err := xenapi.PBD.GetHost(session, pbdRef)
			check(err)
			attached, err := xenapi.PBD.GetCurrentlyAttached(session, pbdRef)
			check(err)
			if pbdHost == host && attached {
				destSr, found = ref, true
				break
			}
		}
		if found {
			break
		}
	}
	if !found {
		panic("no destination SR reachable from the VM's resident host was found")
	}

	// PoolMigrate returns the disk's new VDI: the copy on the destination SR replaces the original.
	vdi, err = xenapi.VDI.PoolMigrate(session, vdi, destSr, map[string]string{})
	check(err)

	nowOn, _ := xenapi.VDI.GetSR(session, vdi)
	nowName, _ := xenapi.SR.GetNameLabel(session, nowOn)
	fmt.Printf("Disk moved to:  %s\n", nowName)

	// Tidy up: the VM and the disks it now owns.
	check(xenapi.VM.HardShutdown(session, vm))
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: storage-migrate")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Disk is on SR: Shared NFS
Disk moved to:  Local storage
OK: storage-migrate
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/migration/StorageMigrate.java`](../../java/src/main/java/com/xenserver/samples/migration/StorageMigrate.java)

```java
package com.xenserver.samples.migration;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.Helpers.awaitTask;
import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.diskVdis;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class StorageMigrate {
    private StorageMigrate() {
    }

    /**
     * Storage live-migration.
     *
     * <p>Move a running VM's virtual disk to a different storage repository while the VM keeps running —
     * live storage migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
     *
     * <p>Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
     * so this works on a throwaway copy of sourceVm, a VM with a guest OS and PV drivers. (A halted VM's
     * disk moves too, without the guest; what VDI.poolMigrate always needs is a VM to move the disk for -
     * a VDI no VBD points at fails VDI_NEEDS_VM_FOR_MIGRATE.)
     *
     * <p>Run it:
     *
     * <pre>{@code
     * StorageMigrate.run("https://xenserver", "root", password, "web-01", "sdk-example-storagemigrate");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String sourceVm, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = copyOfGuest(conn, sourceVm, newVmName);
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);
        VDI vdi = diskVdis(conn, vm).iterator().next();
        SR sourceSr = vdi.getSR(conn);
        System.out.println("Disk is on SR: " + sourceSr.getNameLabel(conn));

        // Pick a different SR that holds disks and that the VM's host can reach (an attached PBD there).
        Host host = vm.getResidentOn(conn);
        SR destSr = null;
        for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet()) {
            SR.Record r = e.getValue();
            if (e.getKey().equals(sourceSr) || "iso".equals(r.contentType)
                    || "iso".equals(r.type) || "udev".equals(r.type))
                continue;
            boolean reachable = false;
            for (PBD pbd : r.PBDs)
                if (pbd.getHost(conn).equals(host) && pbd.getCurrentlyAttached(conn)) { reachable = true; break; }
            if (reachable) { destSr = e.getKey(); break; }
        }
        // poolMigrate returns the disk's new VDI: the copy on the destination SR replaces the original.
        // Copying a disk takes minutes, so run it as a task (see awaitTask).
        vdi = new VDI(awaitTask(conn, vdi.poolMigrateAsync(conn, destSr, new java.util.HashMap<>())));

        System.out.println("Disk moved to:  " + vdi.getSR(conn).getNameLabel(conn));

        // Tidy up: the VM and the disks it now owns.
        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: storage-migrate");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Disk is on SR: Shared NFS
Disk moved to:  iSCSI storage
OK: storage-migrate
```

</details>
