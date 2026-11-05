<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Back up with changed block tracking

Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which blocks differ, then release the older snapshot's data while keeping the change metadata the next incremental needs.

Workflow `changed-block-tracking`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Storage/ChangedBlockTracking.cs`](../../csharp/Storage/ChangedBlockTracking.cs)

```csharp
/// <summary>
/// Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which
/// blocks differ, then release the older snapshot's data while keeping the change metadata the next
/// incremental needs.
/// </summary>
/// <example>
/// <code>
/// Workflows.ChangedBlockTracking("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ChangedBlockTracking(string url, string user, string password)
{
    var session = Connect(url, user, password);

    var vm = VM.get_all_records(session).First(kv =>
        !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot &&
        kv.Value.VBDs.Count > 0);
    Console.WriteLine($"Backing up {vm.Value.name_label}");

    // CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it.
    // It can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
    var live = FirstDisk(session, vm.Key.opaque_ref);
    var wasEnabled = VDI.get_cbt_enabled(session, live);
    if (!wasEnabled) VDI.enable_cbt(session, live);

    var first = VM.snapshot(session, vm.Key.opaque_ref, "cbt-backup-1");
    var second = VM.snapshot(session, vm.Key.opaque_ref, "cbt-backup-2");
    var vdiFrom = FirstDisk(session, first.opaque_ref);
    var vdiTo = FirstDisk(session, second.opaque_ref);

    // One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup reads
    // only those blocks, over NBD.
    var bitmap = Convert.FromBase64String(VDI.list_changed_blocks(session, vdiFrom, vdiTo));
    var changed = bitmap.Sum(b => System.Numerics.BitOperations.PopCount(b));
    Console.WriteLine($"  {changed} blocks of {bitmap.Length * 8} changed "
                      + $"({changed * 64 / 1024.0:F1} MiB to copy, not "
                      + $"{VDI.get_virtual_size(session, vdiTo) / (1024.0 * 1024):F1} MiB)");

    // Release the older snapshot's blocks but keep its change metadata, so the next incremental can
    // still diff against it. data_destroy refuses a disk that a VM still uses (VDI_IN_USE), so drop the
    // older snapshot's VM record first, as a backup tool does. The VDI record stays; its type changes.
    VM.destroy(session, first.opaque_ref);
    VDI.data_destroy(session, vdiFrom);
    Console.WriteLine($"  older snapshot is now type={VDI.get_type(session, vdiFrom)}, "
                      + $"still cbt_enabled={VDI.get_cbt_enabled(session, vdiFrom)}");

    // Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own disk
    // if this example switched it on.
    DestroyVmAndDisks(session, second.opaque_ref);
    VDI.destroy(session, vdiFrom);
    if (!wasEnabled) VDI.disable_cbt(session, live);
    Console.WriteLine("OK: changed-block-tracking");
    session.logout();
}

/// <summary>The VDI behind a VM's first real disk (a CD drive is a VBD too).</summary>
private static string FirstDisk(Session session, string vmRef)
{
    foreach (var vbdRef in VM.get_VBDs(session, vmRef))
        if (VBD.get_type(session, vbdRef.opaque_ref) == vbd_type.Disk)
            return VBD.get_VDI(session, vbdRef.opaque_ref).opaque_ref;
    throw new Exception("no disk found");
}
```

<details><summary>Example output</summary>

```text
Backing up web-01
  12759 blocks of 409600 changed (797.4 MiB to copy, not 25600.0 MiB)
  older snapshot is now type=cbt_metadata, still cbt_enabled=True
OK: changed-block-tracking
```

</details>

## Python

Source: [`python/storage/changed_block_tracking.py`](../../python/storage/changed_block_tracking.py)

```python
"""Back up with changed block tracking.

Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which
blocks differ, then release the older snapshot's data while keeping the change metadata the next
incremental needs.
"""

import base64

from connection import connect
from helpers import destroy_vm_and_disks


def changed_block_tracking(url, username, password):
    """Walk an incremental backup: enable CBT, snapshot twice, ask which blocks differ,
    then release the older snapshot's data while keeping the metadata.

    This is the whole point of CBT. Without it an incremental has to read the entire disk
    to find out what moved; with it the server answers directly, and data_destroy means
    the chain of snapshots you diff against costs metadata rather than disk."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = next(ref for ref, v in x.VM.get_all_records().items()
              if not v["is_a_template"] and not v["is_control_domain"]
              and not v["is_a_snapshot"] and v["VBDs"])
    print("Backing up %s" % x.VM.get_name_label(vm))

    # CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it.
    # It can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
    live = first_disk(x, vm)
    was_enabled = x.VDI.get_cbt_enabled(live)
    if not was_enabled:
        x.VDI.enable_cbt(live)

    first = x.VM.snapshot(vm, "cbt-backup-1")
    second = x.VM.snapshot(vm, "cbt-backup-2")
    vdi_from, vdi_to = first_disk(x, first), first_disk(x, second)

    # One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup
    # reads only those blocks, over NBD.
    bitmap = base64.b64decode(x.VDI.list_changed_blocks(vdi_from, vdi_to))
    changed = sum(bin(byte).count("1") for byte in bitmap)
    print("  %d blocks of %d changed (%.1f MiB to copy, not %.1f MiB)"
          % (changed, len(bitmap) * 8, changed * 64 / 1024.0,
             int(x.VDI.get_virtual_size(vdi_to)) / (1024.0 ** 2)))

    # Release the older snapshot's blocks but keep its change metadata, so the next incremental can
    # still diff against it. data_destroy refuses a disk that a VM still uses (VDI_IN_USE), so drop the
    # older snapshot's VM record first, as a backup tool does. The VDI record stays; its type changes.
    x.VM.destroy(first)
    x.VDI.data_destroy(vdi_from)
    print("  older snapshot is now type=%s, still cbt_enabled=%s"
          % (x.VDI.get_type(vdi_from), x.VDI.get_cbt_enabled(vdi_from)))

    # Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own disk
    # if this example switched it on.
    destroy_vm_and_disks(session, second)
    x.VDI.destroy(vdi_from)
    if not was_enabled:
        x.VDI.disable_cbt(live)
    print("OK: changed-block-tracking")
    session.logout()


def first_disk(x, vm):
    """The VDI behind a VM's first real disk (a CD drive is a VBD too)."""
    for vbd in x.VM.get_VBDs(vm):
        if x.VBD.get_type(vbd) == "Disk":
            return x.VBD.get_VDI(vbd)
    raise Exception("no disk found")
```

<details><summary>Example output</summary>

```text
Backing up web-01
  12832 blocks of 409600 changed (802.0 MiB to copy, not 25600.0 MiB)
  older snapshot is now type=cbt_metadata, still cbt_enabled=True
OK: changed-block-tracking
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/ChangedBlockTracking.java`](../../java/src/main/java/com/xenserver/samples/storage/ChangedBlockTracking.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.PoolConnection.connect;

public final class ChangedBlockTracking {
    private ChangedBlockTracking() {
    }

    /**
     * Back up with changed block tracking.
     *
     * <p>Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which
     * blocks differ, then release the older snapshot's data while keeping the change metadata the next
     * incremental needs.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ChangedBlockTracking.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = null;
            VM.Record record = null;
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record v = e.getValue();
                if (!v.isATemplate && !v.isControlDomain && !v.isASnapshot && !v.VBDs.isEmpty()) {
                    vm = e.getKey(); record = v; break;
                }
            }
            if (vm == null) throw new Exception("no VM with a disk");
            System.out.println("Backing up " + record.nameLabel);

            // CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it.
            // It can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
            VDI live = firstDisk(conn, vm);
            boolean wasEnabled = live.getCbtEnabled(conn);
            if (!wasEnabled) live.enableCbt(conn);

            VM first = vm.snapshot(conn, "cbt-backup-1");
            VM second = vm.snapshot(conn, "cbt-backup-2");
            VDI vdiFrom = firstDisk(conn, first);
            VDI vdiTo = firstDisk(conn, second);

            // One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup
            // reads only those blocks, over NBD.
            byte[] bitmap = java.util.Base64.getDecoder().decode(vdiFrom.listChangedBlocks(conn, vdiTo));
            int changed = 0;
            for (byte b : bitmap) changed += Integer.bitCount(b & 0xFF);
            System.out.printf("  %d blocks of %d changed (%.1f MiB to copy, not %.1f MiB)%n",
                changed, bitmap.length * 8, changed * 64 / 1024.0,
                vdiTo.getVirtualSize(conn) / (1024.0 * 1024));

            // Release the older snapshot's blocks but keep its change metadata, so the next incremental
            // can still diff against it. data_destroy refuses a disk that a VM still uses (VDI_IN_USE), so
            // drop the older snapshot's VM record first, as a backup tool does. The VDI record stays; its
            // type changes.
            first.destroy(conn);
            vdiFrom.dataDestroy(conn);
            System.out.printf("  older snapshot is now type=%s, still cbt_enabled=%b%n",
                vdiFrom.getType(conn), vdiFrom.getCbtEnabled(conn));

            // Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own
            // disk if this example switched it on.
            destroyVmAndDisks(conn, second);
            vdiFrom.destroy(conn);
            if (!wasEnabled) live.disableCbt(conn);
            System.out.println("OK: changed-block-tracking");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * The VDI behind a VM's first real disk (a CD drive is a VBD too).
     */
    private static VDI firstDisk(Connection conn, VM vm) throws Exception {
        for (VBD vbd : vm.getVBDs(conn))
            if (vbd.getType(conn) == Types.VbdType.DISK)
                return vbd.getVDI(conn);
        throw new Exception("no disk found");
    }
}
```

<details><summary>Example output</summary>

```text
Backing up web-01
  12962 blocks of 409600 changed (810.1 MiB to copy, not 25600.0 MiB)
  older snapshot is now type=cbt_metadata, still cbt_enabled=true
OK: changed-block-tracking
```

</details>

## Go

Source: [`go/changed_block_tracking.go`](../../go/changed_block_tracking.go)

```go
package main

import (
	"encoding/base64"
	"fmt"
	"math/bits"

	"go/xenapi"
)

// changedBlockTracking - Back up with changed block tracking.
//
// Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which
// blocks differ, then release the older snapshot's data while keeping the change metadata the next
// incremental needs.
func changedBlockTracking(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vm xenapi.VMRef
	var record xenapi.VMRecord
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && !v.IsASnapshot && len(v.VBDs) > 0 {
			vm, record = ref, v
			break
		}
	}
	fmt.Printf("Backing up %s\n", record.NameLabel)

	// CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it. It
	// can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
	live := firstDisk(session, vm)
	wasEnabled, err := xenapi.VDI.GetCbtEnabled(session, live)
	check(err)
	if !wasEnabled {
		check(xenapi.VDI.EnableCbt(session, live))
	}

	first, err := xenapi.VM.Snapshot(session, vm, "cbt-backup-1", nil)
	check(err)
	second, err := xenapi.VM.Snapshot(session, vm, "cbt-backup-2", nil)
	check(err)
	vdiFrom, vdiTo := firstDisk(session, first), firstDisk(session, second)

	// One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup reads
	// only those blocks, over NBD.
	encoded, err := xenapi.VDI.ListChangedBlocks(session, vdiFrom, vdiTo)
	check(err)
	bitmap, err := base64.StdEncoding.DecodeString(encoded)
	check(err)
	changed := 0
	for _, b := range bitmap {
		changed += bits.OnesCount8(b)
	}
	size, err := xenapi.VDI.GetVirtualSize(session, vdiTo)
	check(err)
	fmt.Printf("  %d blocks of %d changed (%.1f MiB to copy, not %.1f MiB)\n",
		changed, len(bitmap)*8, float64(changed)*64/1024, float64(size)/(1024*1024))

	// Release the older snapshot's blocks but keep its change metadata, so the next incremental can
	// still diff against it. DataDestroy refuses a disk that a VM still uses (VDI_IN_USE), so drop the
	// older snapshot's VM record first, as a backup tool does. The VDI record stays; its type changes.
	check(xenapi.VM.Destroy(session, first))
	check(xenapi.VDI.DataDestroy(session, vdiFrom))
	vdiType, err := xenapi.VDI.GetType(session, vdiFrom)
	check(err)
	stillTracked, err := xenapi.VDI.GetCbtEnabled(session, vdiFrom)
	check(err)
	fmt.Printf("  older snapshot is now type=%s, still cbt_enabled=%t\n", vdiType, stillTracked)

	// Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own disk if
	// this example switched it on.
	destroyVMAndDisks(session, second)
	check(xenapi.VDI.Destroy(session, vdiFrom))
	if !wasEnabled {
		check(xenapi.VDI.DisableCbt(session, live))
	}
	fmt.Println("OK: changed-block-tracking")
}

// firstDisk returns the VDI behind a VM's first real disk (a CD drive is a VBD too).
func firstDisk(session *xenapi.Session, vm xenapi.VMRef) xenapi.VDIRef {
	vbds, err := xenapi.VM.GetVBDs(session, vm)
	check(err)
	for _, vbd := range vbds {
		vbdType, err := xenapi.VBD.GetType(session, vbd)
		check(err)
		if vbdType == xenapi.VbdTypeDisk {
			vdi, err := xenapi.VBD.GetVDI(session, vbd)
			check(err)
			return vdi
		}
	}
	panic("no disk found")
}
```

<details><summary>Example output</summary>

```text
Backing up db-01
  12542 blocks of 409600 changed (783.9 MiB to copy, not 25600.0 MiB)
  older snapshot is now type=cbt_metadata, still cbt_enabled=true
OK: changed-block-tracking
```

</details>

## PowerShell

Source: [`powershell/Storage/Invoke-ChangedBlockTracking.ps1`](../../powershell/Storage/Invoke-ChangedBlockTracking.ps1)

```powershell
function Invoke-ChangedBlockTracking {
    <#
    .SYNOPSIS
        Back up with changed block tracking.
    .DESCRIPTION
        Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which
        blocks differ, then release the older snapshot's data while keeping the change metadata the next
        incremental needs.
    .EXAMPLE
        Invoke-ChangedBlockTracking -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.VBDs.Count -gt 0
    } | Select-Object -First 1
    Write-Host "Backing up $($vm.name_label)"

    # CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it. It
    # can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
    $live = Get-FirstDisk -Snapshot $vm
    $wasEnabled = (Get-XenVDI -Ref $live).cbt_enabled
    if (-not $wasEnabled) { Invoke-XenVDI -Ref $live -XenAction EnableCbt }

    $first = Invoke-XenVM -VM $vm -XenAction Snapshot -NewName 'cbt-backup-1' -PassThru
    $second = Invoke-XenVM -VM $vm -XenAction Snapshot -NewName 'cbt-backup-2' -PassThru
    # Re-fetch the snapshots: the object -PassThru hands back is the VM as it was when created, and its
    # disks are attached a moment later, so its VBDs list is empty.
    $vdiFrom = Get-FirstDisk -Snapshot (Get-XenVM -Ref $first.opaque_ref)
    $vdiTo = Get-FirstDisk -Snapshot (Get-XenVM -Ref $second.opaque_ref)

    # One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup reads
    # only those blocks, over NBD.
    # BOTH disks go in the dynamic parameters. -Ref only names the object the confirmation prompt talks
    # about; the call itself is made from -VdiFrom and -VdiTo, so passing only one sends a null for the
    # other and the server answers HANDLE_INVALID with an empty reference. (Dynamic parameters are keyed
    # on -XenAction, which is why they never show in (Get-Command).Parameters.)
    $encoded = Invoke-XenVDI -Ref $vdiFrom -XenAction ListChangedBlocks `
        -VdiFrom (Get-XenVDI -Ref $vdiFrom | ConvertTo-XenRef) `
        -VdiTo (Get-XenVDI -Ref $vdiTo | ConvertTo-XenRef) -PassThru
    $bitmap = [Convert]::FromBase64String($encoded)
    $changed = 0
    foreach ($byte in $bitmap) {
        $b = $byte
        while ($b) { $changed += $b -band 1; $b = $b -shr 1 }
    }
    $size = (Get-XenVDI -Ref $vdiTo).virtual_size
    Write-Host ("  {0} blocks of {1} changed ({2:N1} MiB to copy, not {3:N1} MiB)" -f
        $changed, ($bitmap.Length * 8), ($changed * 64 / 1024), ($size / 1MB))

    # Release the older snapshot's blocks but keep its change metadata, so the next incremental can
    # still diff against it. DataDestroy refuses a disk that a VM still uses (VDI_IN_USE), so remove the
    # older snapshot's VM record first, as a backup tool does. The VDI record stays; its type changes.
    Remove-XenVM -Ref $first.opaque_ref
    Invoke-XenVDI -Ref $vdiFrom -XenAction DataDestroy
    $after = Get-XenVDI -Ref $vdiFrom
    Write-Host "  older snapshot is now type=$($after.type), still cbt_enabled=$($after.cbt_enabled)"

    # Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own disk if
    # this example switched it on.
    Remove-VmAndDisks -Ref $second.opaque_ref
    Remove-XenVDI -Ref $vdiFrom
    if (-not $wasEnabled) { Invoke-XenVDI -Ref $live -XenAction DisableCbt }
    Write-Host "OK: changed-block-tracking"
    $session | Disconnect-XenServer
}

function Get-FirstDisk {
    <#
    .SYNOPSIS
        The VDI behind a snapshot's first real disk (a CD drive is a VBD too).
    #>
    param([Parameter(Mandatory = $true)]$Snapshot)
    foreach ($vbdRef in $Snapshot.VBDs) {
        $vbd = Get-XenVBD -Ref $vbdRef.opaque_ref
        if ($vbd.type -eq 'Disk') { return $vbd.VDI.opaque_ref }
    }
    throw "no disk found"
}
```

<details><summary>Example output</summary>

```text
Backing up web-01
  12639 blocks of 409600 changed (789.9 MiB to copy, not 25,600.0 MiB)
  older snapshot is now type=cbt_metadata, still cbt_enabled=True
OK: changed-block-tracking
```

</details>

## xe CLI

Source: [`cli/storage/changed-block-tracking.sh`](../../cli/storage/changed-block-tracking.sh)

```bash
# Back up with changed block tracking.
#
# Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which blocks
# differ, then release the older snapshot's data while keeping the change metadata the next incremental needs.
#
# Run it:
#   ./workflows.sh changed-block-tracking https://xenserver root "$password"

changed_block_tracking() {
    vm=""
    for candidate in $(each_csv "$(xe vm-list is-a-template=false is-control-domain=false is-a-snapshot=false --minimal)"); do
        [ -n "$(first_disk_vdi "$candidate")" ] || continue
        vm=$candidate; break
    done
    [ -n "$vm" ] || { echo "no VM with a disk was found" >&2; exit 1; }
    echo "Backing up $(xe vm-param-get uuid=$vm param-name=name-label)"

    # CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it. It
    # can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
    live=$(first_disk_vdi "$vm")
    was_enabled=$(xe vdi-param-get uuid=$live param-name=cbt-enabled)
    [ "$was_enabled" = "true" ] || xe vdi-enable-cbt uuid=$live

    first=$(xe vm-snapshot uuid=$vm new-name-label=cbt-backup-1)
    second=$(xe vm-snapshot uuid=$vm new-name-label=cbt-backup-2)
    vdi_from=$(first_disk_vdi "$first")
    vdi_to=$(first_disk_vdi "$second")

    # One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup reads only
    # those blocks, over NBD. Counting the bits needs a decoder, which bash is not - so report the size
    # of the answer and let the language examples do the arithmetic.
    encoded=$(xe vdi-list-changed-blocks vdi-from-uuid=$vdi_from vdi-to-uuid=$vdi_to)
    size=$(xe vdi-param-get uuid=$vdi_to param-name=virtual-size)
    echo "  bitmap of ${#encoded} base64 chars covers $((size / 65536)) blocks of 64 KiB"

    # Release the older snapshot's blocks but keep its change metadata, so the next incremental can still
    # diff against it. vdi-data-destroy refuses a disk that a VM still uses (VDI_IN_USE), so drop the older
    # snapshot's VM record first (snapshot-destroy leaves its disk), as a backup tool does. The VDI record
    # stays; its type changes.
    xe snapshot-destroy uuid=$first
    xe vdi-data-destroy uuid=$vdi_from
    echo "  older snapshot is now type=$(xe vdi-param-get uuid=$vdi_from param-name=type), still cbt-enabled=$(xe vdi-param-get uuid=$vdi_from param-name=cbt-enabled)"

    # Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own disk if this
    # example switched it on.
    xe snapshot-uninstall snapshot-uuid=$second force=true
    xe vdi-destroy uuid=$vdi_from
    [ "$was_enabled" = "true" ] || xe vdi-disable-cbt uuid=$live
    echo "OK: changed-block-tracking"
}
```

<details><summary>Example output</summary>

```text
Backing up web-01
  bitmap of 68268 base64 chars covers 409600 blocks of 64 KiB
  older snapshot is now type=cbt_metadata, still cbt-enabled=true
OK: changed-block-tracking
```

</details>
