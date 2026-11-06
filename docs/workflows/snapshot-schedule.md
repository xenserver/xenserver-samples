<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Snapshot schedule

Create a scheduled-snapshot policy, attach a VM to it, run it on demand (the xe CLI version only creates and removes the schedule) and watch the retention limit prune the oldest snapshot away.

Workflow `snapshot-schedule`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-SnapshotSchedule.ps1`](../../powershell/VirtualMachines/Invoke-SnapshotSchedule.ps1)

```powershell
function Invoke-SnapshotSchedule {
    <#
    .SYNOPSIS
        Snapshot schedule.
    .DESCRIPTION
        Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention
        limit prune the oldest snapshot away.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName,
        [string]$ScheduleName = "sdk-example-schedule"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }

    # RetainedSnapshots is the interesting field: the schedule prunes to it every time it runs.
    $vmss = New-XenVMSS -NameLabel $ScheduleName `
        -NameDescription 'Scheduled snapshots created by the SDK example' `
        -Enabled $true -Type snapshot -Frequency daily -RetainedSnapshots 2 `
        -Schedule @{ hour = '2'; min = '0' } -PassThru
    Write-Host "Created schedule: $($vmss.uuid)"

    Set-XenVM -VM $vm -SnapshotSchedule $vmss.opaque_ref
    Write-Host "Members:          $((Get-XenVMSS -Ref $vmss.opaque_ref).VMs.Count)"

    # Run it three times against a retention of two: the oldest is pruned away. Compare against the
    # snapshots the VM already had, so only the schedule's own are counted (and tidied up below).
    $before = @((Get-XenVM -Ref $vm.opaque_ref).snapshots | ForEach-Object { $_.opaque_ref })
    1..3 | ForEach-Object { Invoke-XenVMSS -Ref $vmss.opaque_ref -XenAction SnapshotNow | Out-Null }
    $kept = @((Get-XenVM -Ref $vm.opaque_ref).snapshots | ForEach-Object { $_.opaque_ref } |
        Where-Object { $before -notcontains $_ })
    Write-Host "Snapshots kept:   $($kept.Count) (retention 2)"

    # Tidy up: a schedule with VMs still on it cannot be destroyed (VMSS_HAS_VM), so take the VM off it
    # first. Destroying the schedule leaves the snapshots it took, so destroy those too, with their disks.
    Set-XenVM -VM $vm -SnapshotSchedule 'OpaqueRef:NULL'
    Remove-XenVMSS -Ref $vmss.opaque_ref
    $kept | ForEach-Object { Remove-VmAndDisks -Ref $_ }
    Write-Host "OK: snapshot-schedule"
    Disconnect-XenServer -Session $session
}
```

<details><summary>Example output</summary>

```text
Created schedule: 00000001-0000-0000-190a-000000000000
Members:          1
Snapshots kept:   2 (retention 2)
OK: snapshot-schedule
```

</details>

## xe CLI

Source: [`cli/virtual-machines/snapshot-schedule.sh`](../../cli/virtual-machines/snapshot-schedule.sh)

```bash
# Snapshot schedule.
#
# Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention limit prune
# the oldest snapshot away.
#
# Run it:
#   ./workflows.sh snapshot-schedule https://xenserver root "$password"

snapshot_schedule() {
    vm=$(vm_uuid web-01)
    # retained-snapshots is the interesting field: the schedule prunes to it every time it runs.
    vmss=$(xe vmss-create name-label=xe-example-schedule type=snapshot frequency=daily retained-snapshots=2)
    echo "Created schedule: $vmss"

    xe vm-param-set uuid=$vm snapshot-schedule=$vmss
    echo "Members:          $(count_csv "$(set_to_csv "$(xe vmss-param-get uuid=$vmss param-name=VMs)")")"

    # xe has no command to run a schedule on demand (the API's VMSS.snapshot_now has no CLI form), so it
    # takes its first snapshot when it next falls due, and from then on keeps the newest retained-snapshots.
    echo "Keeps:            $(xe vmss-param-get uuid=$vmss param-name=retained-snapshots) snapshot(s)"

    # A schedule with VMs still on it cannot be destroyed, so take the VM off it first.
    xe vm-param-set uuid=$vm snapshot-schedule=
    xe vmss-destroy uuid=$vmss
    echo "OK: snapshot-schedule"
}
```

<details><summary>Example output</summary>

```text
Created schedule: 00000001-0000-0000-1c0a-000000000000
Members:          1
Keeps:            2 snapshot(s)
OK: snapshot-schedule
```

</details>

## Python

Source: [`python/virtual_machines/snapshot_schedule.py`](../../python/virtual_machines/snapshot_schedule.py)

```python
"""Snapshot schedule.

Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention
limit prune the oldest snapshot away.

Run it::

    snapshot_schedule("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name


def snapshot_schedule(url, username, password, vm_name, schedule_name="sdk-example-schedule"):
    """Create a scheduled-snapshot policy, attach a VM, run it, and watch retention prune."""
    session = connect(url, username, password)
    vm_ref = vm_by_name(session, vm_name)

    # retained_snapshots is the interesting field: the schedule prunes to it every time it runs.
    vmss_ref = session.xenapi.VMSS.create({
        "name_label": schedule_name,
        "name_description": "Scheduled snapshots created by the SDK example",
        "enabled": True,
        "type": "snapshot",
        "frequency": "daily",
        "retained_snapshots": "2",
        "schedule": {"hour": "2", "min": "0"},
    })
    print("Created schedule: %s" % session.xenapi.VMSS.get_uuid(vmss_ref))

    session.xenapi.VM.set_snapshot_schedule(vm_ref, vmss_ref)
    print("Members:          %d" % len(session.xenapi.VMSS.get_VMs(vmss_ref)))

    # Run it three times against a retention of two: the oldest is pruned away. Compare against the
    # snapshots the VM already had, so only the schedule's own are counted (and tidied up below).
    before = set(session.xenapi.VM.get_snapshots(vm_ref))
    for _ in range(3):
        session.xenapi.VMSS.snapshot_now(vmss_ref)
    kept = [s for s in session.xenapi.VM.get_snapshots(vm_ref) if s not in before]
    print("Snapshots kept:   %d (retention 2)" % len(kept))

    # Tidy up: a schedule with VMs still on it cannot be destroyed (VMSS_HAS_VM), so take the VM off it
    # first. Destroying the schedule leaves the snapshots it took, so destroy those too, with their disks.
    session.xenapi.VM.set_snapshot_schedule(vm_ref, "OpaqueRef:NULL")
    session.xenapi.VMSS.destroy(vmss_ref)
    for snapshot in kept:
        destroy_vm_and_disks(session, snapshot)
    print("OK: snapshot-schedule")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Created schedule: 00000001-0000-0000-120a-000000000000
Members:          1
Snapshots kept:   2 (retention 2)
OK: snapshot-schedule
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/SnapshotSchedule.cs`](../../csharp/VirtualMachines/SnapshotSchedule.cs)

```csharp
/// <summary>
/// Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention limit
/// prune the oldest snapshot away.
/// </summary>
/// <example>
/// <code>
/// Workflows.SnapshotSchedule("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void SnapshotSchedule(string url, string user, string password,
    string vmName, string scheduleName = "sdk-example-schedule")
{
    var session = Connect(url, user, password);
    var vmRef = VmByName(session, vmName);

    // retained_snapshots is the interesting field: the schedule prunes to it every time it runs.
    var vmssRef = VMSS.create(session, new VMSS
    {
        name_label = scheduleName,
        name_description = "Scheduled snapshots created by the SDK example",
        enabled = true,
        type = vmss_type.snapshot,
        frequency = vmss_frequency.daily,
        retained_snapshots = 2,
        schedule = new Dictionary<string, string> { ["hour"] = "2", ["min"] = "0" },
    }).opaque_ref;
    Console.WriteLine($"Created schedule: {VMSS.get_uuid(session, vmssRef)}");

    VM.set_snapshot_schedule(session, vmRef, new XenRef<VMSS>(vmssRef));
    Console.WriteLine($"Members:          {VMSS.get_VMs(session, vmssRef).Count}");

    // Run it three times against a retention of two: the oldest is pruned away. Compare against the
    // snapshots the VM already had, so only the schedule's own are counted (and tidied up below).
    var before = VM.get_snapshots(session, vmRef).Select(s => s.opaque_ref).ToHashSet();
    for (var i = 0; i < 3; i++) VMSS.snapshot_now(session, vmssRef);
    var kept = VM.get_snapshots(session, vmRef).Select(s => s.opaque_ref).Where(s => !before.Contains(s)).ToList();
    Console.WriteLine($"Snapshots kept:   {kept.Count} (retention 2)");

    // Tidy up: a schedule with VMs still on it cannot be destroyed (VMSS_HAS_VM), so take the VM off it
    // first. Destroying the schedule leaves the snapshots it took, so destroy those too, with their disks.
    VM.set_snapshot_schedule(session, vmRef, new XenRef<VMSS>("OpaqueRef:NULL"));
    VMSS.destroy(session, vmssRef);
    foreach (var snapshot in kept) DestroyVmAndDisks(session, snapshot);
    Console.WriteLine("OK: snapshot-schedule");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Created schedule: 00000001-0000-0000-060a-000000000000
Members:          1
Snapshots kept:   2 (retention 2)
OK: snapshot-schedule
```

</details>

## Go

Source: [`go/snapshot_schedule.go`](../../go/snapshot_schedule.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// snapshotSchedule - Snapshot schedule.
//
// Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention
// limit prune the oldest snapshot away.
func snapshotSchedule(url, user, password, vmName, scheduleName string) {
	session := connect(url, user, password)
	vmRef := vmByName(session, vmName)

	// RetainedSnapshots is the interesting field: the schedule prunes to it every time it runs.
	vmssRef, err := xenapi.VMSS.Create(session, xenapi.VMSSRecord{
		NameLabel:         scheduleName,
		NameDescription:   "Scheduled snapshots created by the SDK example",
		Enabled:           true,
		Type:              xenapi.VmssTypeSnapshot,
		Frequency:         xenapi.VmssFrequencyDaily,
		RetainedSnapshots: 2,
		Schedule:          map[string]string{"hour": "2", "min": "0"},
	})
	check(err)
	vmssUUID, _ := xenapi.VMSS.GetUUID(session, vmssRef)
	fmt.Printf("Created schedule: %s\n", vmssUUID)

	check(xenapi.VM.SetSnapshotSchedule(session, vmRef, vmssRef))
	members, _ := xenapi.VMSS.GetVMs(session, vmssRef)
	fmt.Printf("Members:          %d\n", len(members))

	// Run it three times against a retention of two: the oldest is pruned away. Compare against the
	// snapshots the VM already had, so only the schedule's own are counted (and tidied up below).
	existing, err := xenapi.VM.GetSnapshots(session, vmRef)
	check(err)
	before := map[xenapi.VMRef]bool{}
	for _, s := range existing {
		before[s] = true
	}
	for i := 0; i < 3; i++ {
		_, err = xenapi.VMSS.SnapshotNow(session, vmssRef)
		check(err)
	}
	snaps, err := xenapi.VM.GetSnapshots(session, vmRef)
	check(err)
	var kept []xenapi.VMRef
	for _, s := range snaps {
		if !before[s] {
			kept = append(kept, s)
		}
	}
	fmt.Printf("Snapshots kept:   %d (retention 2)\n", len(kept))

	// Tidy up: a schedule with VMs still on it cannot be destroyed (VMSS_HAS_VM), so take the VM off it
	// first. Destroying the schedule leaves the snapshots it took, so destroy those too, with their disks.
	check(xenapi.VM.SetSnapshotSchedule(session, vmRef, "OpaqueRef:NULL"))
	check(xenapi.VMSS.Destroy(session, vmssRef))
	for _, s := range kept {
		destroyVMAndDisks(session, s)
	}
	fmt.Println("OK: snapshot-schedule")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Created schedule: 00000001-0000-0000-130a-000000000000
Members:          1
Snapshots kept:   2 (retention 2)
OK: snapshot-schedule
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/SnapshotSchedule.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/SnapshotSchedule.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VMSS;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class SnapshotSchedule {
    private SnapshotSchedule() {
    }

    /**
     * Snapshot schedule.
     *
     * <p>Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention
     * limit prune the oldest snapshot away.
     */
    public static void run(String url, String user, String password,
            String vmName, String scheduleName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);

        // retainedSnapshots is the interesting field: the schedule prunes to it every time it runs.
        VMSS.Record spec = new VMSS.Record();
        spec.nameLabel = scheduleName;
        spec.nameDescription = "Scheduled snapshots created by the SDK example";
        spec.enabled = true;
        spec.type = Types.VmssType.SNAPSHOT;
        spec.frequency = Types.VmssFrequency.DAILY;
        spec.retainedSnapshots = 2L;
        Map<String, String> when = new HashMap<>();
        when.put("hour", "2");
        when.put("min", "0");
        spec.schedule = when;
        VMSS vmss = VMSS.create(conn, spec);
        System.out.println("Created schedule: " + vmss.getUuid(conn));

        vm.setSnapshotSchedule(conn, vmss);
        System.out.println("Members:          " + vmss.getVMs(conn).size());

        // Run it three times against a retention of two: the oldest is pruned away. Compare against the
        // snapshots the VM already had, so only the schedule's own are counted (and tidied up below).
        Set<VM> before = vm.getSnapshots(conn);
        for (int i = 0; i < 3; i++) {
            vmss.snapshotNow(conn);
        }
        Set<VM> kept = new HashSet<>(vm.getSnapshots(conn));
        kept.removeAll(before);
        System.out.println("Snapshots kept:   " + kept.size() + " (retention 2)");

        // Tidy up: a schedule with VMs still on it cannot be destroyed (VMSS_HAS_VM), so take the VM off it
        // first. Destroying the schedule leaves the snapshots it took, so destroy those too, with their disks.
        vm.setSnapshotSchedule(conn, new VMSS("OpaqueRef:NULL"));
        vmss.destroy(conn);
        for (VM snapshot : kept) destroyVmAndDisks(conn, snapshot);
        System.out.println("OK: snapshot-schedule");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Created schedule: 00000001-0000-0000-1b0a-000000000000
Members:          1
Snapshots kept:   2 (retention 2)
OK: snapshot-schedule
```

</details>
