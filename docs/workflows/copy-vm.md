<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Copy a VM

Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks) — distinct from a fast, copy-on-write clone.

Workflow `copy-vm`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/VirtualMachines/CopyVm.cs`](../../csharp/VirtualMachines/CopyVm.cs)

```csharp
/// <summary>
/// Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks) —
/// distinct from a fast, copy-on-write clone.
/// </summary>
/// <example>
/// <code>
/// Workflows.CopyVm("https://xenserver", "root", password, "db-01", "Shared NFS");
/// </code>
/// </example>
public static void CopyVm(string url, string user, string password,
    string vmName, string srName, string copyName = "sdk-example-copy")
{
    var session = Connect(url, user, password);
    // A full copy needs a halted source; it places an independent set of disks on the chosen SR.
    // VM.copy (like VM.clone) raises VM_BAD_POWER_STATE on a running source, so shut it down first
    // if it's running, and start it back up again after the copy.
    var source = VmByName(session, vmName);
    var (srRef, sr) = SR.get_all_records(session).First(kv => kv.Value.name_label == srName);
    Console.WriteLine($"Copying '{VM.get_name_label(session, source)}' to SR: {sr.name_label}");

    var wasRunning = VM.get_power_state(session, source) == vm_power_state.Running;
    if (wasRunning) VM.clean_shutdown(session, source);

    var copy = VM.copy(session, source, copyName, srRef).opaque_ref;
    Console.WriteLine($"Copied VM:     {VM.get_uuid(session, copy)}");
    Console.WriteLine($"Copy has {VM.get_VBDs(session, copy).Count} VBD(s), is_a_template = {VM.get_is_a_template(session, copy)}");

    if (wasRunning) VM.start(session, source, false, true);

    // Tidy up: destroy the copy and its disks, leaving the source VM intact.
    DestroyVmAndDisks(session, copy);
    Console.WriteLine("Cleaned up the copied VM (left the source intact).");
    Console.WriteLine("OK: copy-vm");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Copying 'db-01' to SR: Shared NFS
Copied VM:     00000001-0000-0000-000a-000000000000
Copy has 1 VBD(s), is_a_template = False
Cleaned up the copied VM (left the source intact).
OK: copy-vm
```

</details>

## Python

Source: [`python/virtual_machines/copy_vm.py`](../../python/virtual_machines/copy_vm.py)

```python
"""Copy a VM.

Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks) —
distinct from a fast, copy-on-write clone.

Run it::

    copy_vm("https://xenserver", "root", password, "db-01", "Shared NFS")
"""

from connection import connect
from helpers import destroy_vm_and_disks, sr_by_name, vm_by_name


def copy_vm(url, username, password, vm_name, sr_name, copy_name="sdk-example-copy"):
    """Make a full, independent copy of the named VM onto the named SR (a deep copy of its disks).

    VM.copy (like VM.clone) only works on a Halted VM - a running source fails with
    VM_BAD_POWER_STATE - so shut it down first if it's running, and start it back up again after
    the copy, rather than assuming the VM is already halted."""
    session = connect(url, username, password)
    # A full copy needs a halted source; it places an independent set of disks on the chosen SR.
    source = vm_by_name(session, vm_name)
    sr_ref = sr_by_name(session, sr_name)
    print("Copying '%s' to SR: %s"
          % (session.xenapi.VM.get_name_label(source), session.xenapi.SR.get_name_label(sr_ref)))

    was_running = session.xenapi.VM.get_power_state(source) == "Running"
    if was_running:
        session.xenapi.VM.clean_shutdown(source)

    copy = session.xenapi.VM.copy(source, copy_name, sr_ref)
    print("Copied VM:     %s" % session.xenapi.VM.get_uuid(copy))
    print("Copy has %d VBD(s), is_a_template = %s"
          % (len(session.xenapi.VM.get_VBDs(copy)), session.xenapi.VM.get_is_a_template(copy)))

    if was_running:
        session.xenapi.VM.start(source, False, True)

    # Tidy up: destroy the copy and its disks, leaving the source VM intact.
    destroy_vm_and_disks(session, copy)
    print("Cleaned up the copied VM (left the source intact).")
    print("OK: copy-vm")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Copying 'db-01' to SR: Shared NFS
Copied VM:     00000001-0000-0000-050a-000000000000
Copy has 1 VBD(s), is_a_template = False
Cleaned up the copied VM (left the source intact).
OK: copy-vm
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/CopyVm.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/CopyVm.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CopyVm {
    private CopyVm() {
    }

    /**
     * Copy a VM.
     *
     * <p>Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks)
     * — distinct from a fast, copy-on-write clone.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CopyVm.run("https://xenserver", "root", password, "db-01", "Shared NFS", "sdk-example-copy");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String vmName, String srName, String copyName) throws Exception {
        Connection conn = connect(url, user, password);
        // A full copy needs a halted source; it places an independent set of disks on the chosen SR.
        VM source = vmByName(conn, vmName);
        SR sr = srByName(conn, srName, false);
        System.out.println("Copying '" + source.getNameLabel(conn) + "' to SR: " + sr.getNameLabel(conn));

        // VM.copy (like VM.clone) requires a Halted source (VM_BAD_POWER_STATE otherwise).
        boolean wasRunning = source.getPowerState(conn) == Types.VmPowerState.RUNNING;
        if (wasRunning) source.cleanShutdown(conn);

        VM copy = source.copy(conn, copyName, sr);
        System.out.println("Copied VM:     " + copy.getUuid(conn));
        System.out.println("Copy has " + copy.getVBDs(conn).size()
                + " VBD(s), is_a_template = " + copy.getIsATemplate(conn));

        if (wasRunning) source.start(conn, false, true);

        // Tidy up: destroy the copy and its disks, leaving the source VM intact.
        destroyVmAndDisks(conn, copy);
        System.out.println("Cleaned up the copied VM (left the source intact).");
        System.out.println("OK: copy-vm");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
Copying 'db-01' to SR: Shared NFS
Copied VM:     00000001-0000-0000-0a0a-000000000000
Copy has 1 VBD(s), is_a_template = false
Cleaned up the copied VM (left the source intact).
OK: copy-vm
```

</details>

## Go

Source: [`go/copy_vm.go`](../../go/copy_vm.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// copyVM - Copy a VM.
//
// Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks)
// — distinct from a fast, copy-on-write clone.
//
// Run it:
//
//	copyVM("https://xenserver", "root", password, "db-01", "Shared NFS", "sdk-example-copy")
func copyVM(url, user, password, vmName, srName, copyName string) {
	session := connect(url, user, password)
	// A full copy needs a halted source; it places an independent set of disks on the chosen SR.
	source := vmByName(session, vmName)
	srRef := srByName(session, srName, false)
	srLabel, _ := xenapi.SR.GetNameLabel(session, srRef)
	srcLabel, _ := xenapi.VM.GetNameLabel(session, source)
	fmt.Printf("Copying '%s' to SR: %s\n", srcLabel, srLabel)

	// VM.Copy (like VM.Clone) requires a Halted source - VM_BAD_POWER_STATE otherwise - so shut a
	// running source down first and start it back up again afterwards, rather than assuming it is
	// already halted.
	wasRunning := false
	if state, _ := xenapi.VM.GetPowerState(session, source); state == xenapi.VMPowerStateRunning {
		wasRunning = true
		check(xenapi.VM.CleanShutdown(session, source))
	}

	copyRef, err := xenapi.VM.Copy(session, source, copyName, srRef)
	check(err)
	uuid, _ := xenapi.VM.GetUUID(session, copyRef)
	vbds, _ := xenapi.VM.GetVBDs(session, copyRef)
	isTemplate, _ := xenapi.VM.GetIsATemplate(session, copyRef)
	fmt.Printf("Copied VM:     %s\n", uuid)
	fmt.Printf("Copy has %d VBD(s), is_a_template = %v\n", len(vbds), isTemplate)

	if wasRunning {
		check(xenapi.VM.Start(session, source, false, true))
	}

	// Tidy up: destroy the copy and its disks, leaving the source VM intact.
	destroyVMAndDisks(session, copyRef)
	fmt.Println("Cleaned up the copied VM (left the source intact).")
	fmt.Println("OK: copy-vm")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Copying 'db-01' to SR: Shared NFS
Copied VM:     00000001-0000-0000-0a0a-000000000000
Copy has 1 VBD(s), is_a_template = false
Cleaned up the copied VM (left the source intact).
OK: copy-vm
```

</details>

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-CopyVm.ps1`](../../powershell/VirtualMachines/Invoke-CopyVm.ps1)

```powershell
function Invoke-CopyVm {
    <#
    .SYNOPSIS
        Copy a VM.
    .DESCRIPTION
        Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks) —
        distinct from a fast, copy-on-write clone.
    .EXAMPLE
        Invoke-CopyVm -Url https://xenserver -UserName root -Password $password -VmName 'db-01' -SrName 'Shared NFS'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName,
        [Parameter(Mandatory = $true)][string]$SrName,
        [string]$CopyName = "sdk-example-copy"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # A full copy needs a halted source; copy places an independent set of disks on the chosen SR.
    $source = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1
    if (-not $source) { throw "No VM named '$VmName' was found." }
    $sr = Get-XenSR -Name $SrName | Select-Object -First 1
    if (-not $sr) { throw "No SR named '$SrName' was found." }
    Write-Host "Copying '$($source.name_label)' to SR: $($sr.name_label)"

    # VM.copy (like VM.clone) only works on a Halted VM - a running source fails with
    # VM_BAD_POWER_STATE - so shut it down first if it's running, and start it back up again after the
    # copy, rather than assuming the VM is already halted.
    $wasRunning = (Get-XenVM -Ref $source.opaque_ref).power_state -eq 'Running'
    if ($wasRunning) { $source | Invoke-XenVM -XenAction CleanShutdown }

    $copy = $source | Invoke-XenVM -XenAction Copy -NewName $CopyName -SR $sr -PassThru
    Write-Host "Copied VM:     $($copy.uuid)"
    Write-Host "Copy has $(@($copy.VBDs).Count) VBD(s), is_a_template = $($copy.is_a_template)"

    if ($wasRunning) { $source | Invoke-XenVM -XenAction Start }

    # Tidy up: destroy the copy and its disks, leaving the source VM intact.
    Remove-VmAndDisks -Ref $copy.opaque_ref
    Write-Host "Cleaned up the copied VM (left the source intact)."
    Write-Host "OK: copy-vm"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Copying 'db-01' to SR: Shared NFS
Copied VM:     00000001-0000-0000-080a-000000000000
Copy has 1 VBD(s), is_a_template = False
Cleaned up the copied VM (left the source intact).
OK: copy-vm
```

</details>

## xe CLI

Source: [`cli/virtual-machines/copy-vm.sh`](../../cli/virtual-machines/copy-vm.sh)

```bash
# Copy a VM.
#
# Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks) — distinct
# from a fast, copy-on-write clone.
#
# Run it:
#   ./workflows.sh copy-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   sr_name (Shared NFS)

copy_vm() {
    local vm was_running
    vm=$(vm_uuid db-01)
    # vm-copy (like vm-clone) only works on a Halted VM - a running source fails with VM_BAD_POWER_STATE -
    # so shut it down first if it's running, and start it back up again after the copy.
    was_running=$([ "$(xe vm-param-get uuid=$vm param-name=power-state)" = "running" ] && echo true || echo false)
    [ "$was_running" = true ] && xe vm-shutdown uuid=$vm
    copy=$(xe vm-copy uuid=$vm new-name-label=xe-example-copy sr-uuid=$(sr_by_name "$(param sr_name "Shared NFS")"))
    echo "Copied VM: $copy"
    [ "$was_running" = true ] && xe vm-start uuid=$vm
    # Tidy up: vm-uninstall destroys the copy and its disks, leaving the source VM intact.
    xe vm-uninstall uuid=$copy force=true
    echo "OK: copy-vm"
}
```

<details><summary>Sample output</summary>

```text
Copied VM: 00000001-0000-0000-020a-000000000000
OK: copy-vm
```

</details>
