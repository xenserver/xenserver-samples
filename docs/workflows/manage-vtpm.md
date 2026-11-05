<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage a virtual TPM

Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one, and only while it is halted.

Workflow `manage-vtpm`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/VirtualMachines/ManageVtpm.cs`](../../csharp/VirtualMachines/ManageVtpm.cs)

```csharp
/// <summary>
/// Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one, and
/// only while it is halted.
/// </summary>
/// <example>
/// <code>
/// Workflows.ManageVtpm("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ManageVtpm(string url, string user, string password)
{
    var session = Connect(url, user, password);

    // vTPM is not supported for a BIOS-mode VM, only a UEFI one (HVM_boot_params["firmware"] ==
    // "uefi"), so pick one of those rather than any halted VM.
    var candidates = VM.get_all_records(session).Where(kv =>
        !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot &&
        kv.Value.power_state == vm_power_state.Halted && kv.Value.VTPMs.Count == 0 &&
        kv.Value.HVM_boot_params.TryGetValue("firmware", out var firmware) && firmware == "uefi");
    if (!candidates.Any()) throw new Exception("no halted UEFI VM without a vTPM already attached was found");
    var vm = candidates.First();
    Console.WriteLine($"Attaching a vTPM to {vm.Value.name_label}");

    // is_unique=false: the vTPM may be copied along with the VM. A VM may have at most one, and it
    // can only be attached while Halted — the device is presented at boot.
    var vtpm = VTPM.create(session, vm.Key.opaque_ref, false);
    var record = VTPM.get_record(session, vtpm.opaque_ref);
    Console.WriteLine($"  persistence backend: {record.persistence_backend}");
    Console.WriteLine($"  unique to this VM:   {record.is_unique}");
    Console.WriteLine($"  VM now has {VM.get_VTPMs(session, vm.Key.opaque_ref).Count} vTPM(s)");

    // The VM advertises whether another can be added; once it has one, it cannot.
    Console.WriteLine("  can add another:     " +
        VM.get_allowed_operations(session, vm.Key.opaque_ref).Contains(vm_operations.create_vtpm));

    VTPM.destroy(session, vtpm.opaque_ref);
    Console.WriteLine($"  after removal:       {VM.get_VTPMs(session, vm.Key.opaque_ref).Count} vTPM(s)");
    Console.WriteLine("OK: manage-vtpm");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Attaching a vTPM to secure-01
  persistence backend: xapi
  unique to this VM:   False
  VM now has 1 vTPM(s)
  can add another:     False
  after removal:       0 vTPM(s)
OK: manage-vtpm
```

</details>

## Python

Source: [`python/virtual_machines/manage_vtpm.py`](../../python/virtual_machines/manage_vtpm.py)

```python
"""Manage a virtual TPM.

Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one,
and only while it is halted.

Run it::

    manage_vtpm("https://xenserver", "root", password)
"""

from connection import connect


def manage_vtpm(url, username, password):
    """Attach a virtual TPM to a halted VM, read it back, then remove it.

    A VM may have at most one, and it can only be attached while the VM is Halted — the
    device is presented at boot. vTPM is not supported for a BIOS-mode VM, only a UEFI one
    (HVM_boot_params["firmware"] == "uefi"), so pick one of those rather than any halted VM."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = next((ref for ref, v in x.VM.get_all_records().items()
              if not v["is_a_template"] and not v["is_control_domain"]
              and not v["is_a_snapshot"] and v["power_state"] == "Halted"
              and not v["VTPMs"] and v["HVM_boot_params"].get("firmware") == "uefi"), None)
    if vm is None:
        raise RuntimeError("no halted UEFI VM without a vTPM already attached was found")
    print("Attaching a vTPM to %s" % x.VM.get_name_label(vm))

    vtpm = x.VTPM.create(vm, False)   # is_unique=False: the vTPM may be copied with the VM
    record = x.VTPM.get_record(vtpm)
    print("  persistence backend: %s" % record["persistence_backend"])
    print("  unique to this VM:   %s" % record["is_unique"])
    print("  VM now has %d vTPM(s)" % len(x.VM.get_VTPMs(vm)))

    # The VM advertises whether another can be added; once it has one, it cannot.
    print("  can add another:     %s" % ("create_vtpm" in x.VM.get_allowed_operations(vm)))

    x.VTPM.destroy(vtpm)
    print("  after removal:       %d vTPM(s)" % len(x.VM.get_VTPMs(vm)))
    print("OK: manage-vtpm")
    session.logout()
```

<details><summary>Example output</summary>

```text
Attaching a vTPM to secure-01
  persistence backend: xapi
  unique to this VM:   False
  VM now has 1 vTPM(s)
  can add another:     False
  after removal:       0 vTPM(s)
OK: manage-vtpm
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/ManageVtpm.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/ManageVtpm.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VTPM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVtpm {
    private ManageVtpm() {
    }

    /**
     * Manage a virtual TPM.
     *
     * <p>Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one,
     * and only while it is halted.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageVtpm.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // vTPM is not supported for a BIOS-mode VM, only a UEFI one (HVM_boot_params["firmware"]
            // == "uefi"), so pick one of those rather than any halted VM.
            VM vm = null;
            VM.Record record = null;
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record v = e.getValue();
                if (!v.isATemplate && !v.isControlDomain && !v.isASnapshot
                        && v.powerState == Types.VmPowerState.HALTED && v.VTPMs.isEmpty()
                        && "uefi".equals(v.HVMBootParams.get("firmware"))) {
                    vm = e.getKey(); record = v; break;
                }
            }
            if (vm == null) throw new Exception("no halted UEFI VM without a vTPM already attached was found");
            System.out.println("Attaching a vTPM to " + record.nameLabel);

            // isUnique=false: the vTPM may be copied along with the VM. A VM may have at most one, and
            // it can only be attached while Halted — the device is presented at boot.
            VTPM vtpm = VTPM.create(conn, vm, false);
            VTPM.Record vtpmRecord = vtpm.getRecord(conn);
            System.out.println("  persistence backend: " + vtpmRecord.persistenceBackend);
            System.out.println("  unique to this VM:   " + vtpmRecord.isUnique);
            System.out.println("  VM now has " + vm.getVTPMs(conn).size() + " vTPM(s)");

            // The VM advertises whether another can be added; once it has one, it cannot.
            System.out.println("  can add another:     "
                + vm.getAllowedOperations(conn).contains(Types.VmOperations.CREATE_VTPM));

            vtpm.destroy(conn);
            System.out.println("  after removal:       " + vm.getVTPMs(conn).size() + " vTPM(s)");
            System.out.println("OK: manage-vtpm");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
Attaching a vTPM to secure-01
  persistence backend: xapi
  unique to this VM:   false
  VM now has 1 vTPM(s)
  can add another:     false
  after removal:       0 vTPM(s)
OK: manage-vtpm
```

</details>

## Go

Source: [`go/manage_vtpm.go`](../../go/manage_vtpm.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// manageVtpm - Manage a virtual TPM.
//
// Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one,
// and only while it is halted.
func manageVtpm(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vm xenapi.VMRef
	var record xenapi.VMRecord
	found := false
	// vTPM is not supported for a BIOS-mode VM, only a UEFI one (HVM_boot_params["firmware"] ==
	// "uefi"), so pick one of those rather than any halted VM.
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && !v.IsASnapshot &&
			v.PowerState == xenapi.VMPowerStateHalted && len(v.VTPMs) == 0 &&
			v.HVMBootParams["firmware"] == "uefi" {
			vm, record, found = ref, v, true
			break
		}
	}
	if !found {
		panic("no halted UEFI VM without a vTPM already attached was found")
	}
	fmt.Printf("Attaching a vTPM to %s\n", record.NameLabel)

	// isUnique=false: the vTPM may be copied along with the VM. A VM may have at most one, and it can
	// only be attached while Halted — the device is presented at boot.
	vtpm, err := xenapi.VTPM.Create(session, vm, false)
	check(err)
	vtpmRecord, err := xenapi.VTPM.GetRecord(session, vtpm)
	check(err)
	fmt.Printf("  persistence backend: %s\n", vtpmRecord.PersistenceBackend)
	fmt.Printf("  unique to this VM:   %t\n", vtpmRecord.IsUnique)
	attached, err := xenapi.VM.GetVTPMs(session, vm)
	check(err)
	fmt.Printf("  VM now has %d vTPM(s)\n", len(attached))

	// The VM advertises whether another can be added; once it has one, it cannot.
	ops, err := xenapi.VM.GetAllowedOperations(session, vm)
	check(err)
	canAdd := false
	for _, op := range ops {
		if op == xenapi.VMOperationsCreateVtpm {
			canAdd = true
		}
	}
	fmt.Printf("  can add another:     %t\n", canAdd)

	check(xenapi.VTPM.Destroy(session, vtpm))
	attached, err = xenapi.VM.GetVTPMs(session, vm)
	check(err)
	fmt.Printf("  after removal:       %d vTPM(s)\n", len(attached))
	fmt.Println("OK: manage-vtpm")
}
```

<details><summary>Example output</summary>

```text
Attaching a vTPM to secure-01
  persistence backend: xapi
  unique to this VM:   false
  VM now has 1 vTPM(s)
  can add another:     false
  after removal:       0 vTPM(s)
OK: manage-vtpm
```

</details>

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-ManageVtpm.ps1`](../../powershell/VirtualMachines/Invoke-ManageVtpm.ps1)

```powershell
function Invoke-ManageVtpm {
    <#
    .SYNOPSIS
        Manage a virtual TPM.
    .DESCRIPTION
        Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one,
        and only while it is halted.
    .EXAMPLE
        Invoke-ManageVtpm -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # vTPM is not supported for a BIOS-mode VM, only a UEFI one (HVM_boot_params["firmware"] ==
    # "uefi"), so pick one of those rather than any halted VM.
    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.power_state -eq 'Halted' -and $_.VTPMs.Count -eq 0 -and
        $_.HVM_boot_params['firmware'] -eq 'uefi'
    } | Select-Object -First 1
    if (-not $vm) { throw "No halted UEFI VM without a vTPM already attached was found." }
    Write-Host "Attaching a vTPM to $($vm.name_label)"

    # IsUnique false: the vTPM may be copied along with the VM. A VM may have at most one, and it can
    # only be attached while Halted — the device is presented at boot.
    $vtpm = New-XenVTPM -VM $vm.opaque_ref -IsUnique $false -PassThru
    Write-Host "  persistence backend: $($vtpm.persistence_backend)"
    Write-Host "  unique to this VM:   $($vtpm.is_unique)"
    Write-Host "  VM now has $(@((Get-XenVM -Ref $vm.opaque_ref).VTPMs).Count) vTPM(s)"

    # The VM advertises whether another can be added; once it has one, it cannot.
    Write-Host "  can add another:     $((Get-XenVM -Ref $vm.opaque_ref).allowed_operations -contains 'create_vtpm')"

    Remove-XenVTPM -Ref $vtpm.opaque_ref
    Write-Host "  after removal:       $(@((Get-XenVM -Ref $vm.opaque_ref).VTPMs).Count) vTPM(s)"
    Write-Host "OK: manage-vtpm"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Attaching a vTPM to secure-01
  persistence backend: xapi
  unique to this VM:   False
  VM now has 1 vTPM(s)
  can add another:     False
  after removal:       0 vTPM(s)
OK: manage-vtpm
```

</details>

## xe CLI

Source: [`cli/virtual-machines/manage-vtpm.sh`](../../cli/virtual-machines/manage-vtpm.sh)

```bash
# Manage a virtual TPM.
#
# Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one, and only
# while it is halted.
#
# Run it:
#   ./workflows.sh manage-vtpm https://xenserver root "$password"

manage_vtpm() {
    # A halted VM with no vTPM yet. A VM may have at most one, and it can only be attached while halted
    # - the device is presented to the guest at boot. vTPM is not supported for a BIOS-mode VM, only a
    # UEFI one (HVM-boot-params:firmware = uefi), so pick one of those rather than any halted VM.
    vm=""
    for v in $(each_csv "$(xe vm-list power-state=halted --minimal)"); do
        [ -z "$(xe vm-param-get uuid=$v param-name=vtpms)" ] &&
        [ "$(xe vm-param-get uuid=$v param-name=HVM-boot-params param-key=firmware 2>/dev/null)" = "uefi" ] &&
            { vm=$v; break; }
    done
    [ -n "$vm" ] || { echo "no halted UEFI VM without a vTPM already attached was found" >&2; exit 1; }
    echo "Attaching a vTPM to $(xe vm-param-get uuid=$vm param-name=name-label)"

    vtpm=$(xe vtpm-create vm-uuid=$vm is-unique=false)
    echo "  unique to this VM:   $(xe vtpm-param-get uuid=$vtpm param-name=is_unique)"
    echo "  protected:           $(xe vtpm-param-get uuid=$vtpm param-name=is_protected)"
    echo "  VM now has $(count_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=vtpms)")") vTPM(s)"

    # The VM advertises whether another can be added; once it has one, it cannot.
    case "$(xe vm-param-get uuid=$vm param-name=allowed-operations)" in
        *create_vtpm*) echo "  can add another:     true" ;;
        *)             echo "  can add another:     false" ;;
    esac

    xe vtpm-destroy uuid=$vtpm --force       # xe insists: the vTPM's secrets are destroyed with it
    echo "  after removal:       $(count_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=vtpms)")") vTPM(s)"
    echo "OK: manage-vtpm"
}
```

<details><summary>Example output</summary>

```text
Attaching a vTPM to secure-01
  unique to this VM:   false
  protected:           false
  VM now has 1 vTPM(s)
  can add another:     false
  after removal:       0 vTPM(s)
OK: manage-vtpm
```

</details>
