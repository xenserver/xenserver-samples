<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Cross-pool copy a VM

Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the destination, then send a copy of the VM from the source. Takes the destination pool's URL as an extra argument after the password.

**Requires:** a second pool.

Workflow `cross-pool-copy-vm`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/VirtualMachines/CrossPoolCopyVm.cs`](../../csharp/VirtualMachines/CrossPoolCopyVm.cs)

```csharp
/// <summary>
/// Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the
/// destination, then send a copy of the VM from the source. Takes the destination pool's URL as an extra
/// argument after the password.
/// </summary>
/// <example>
/// <code>
/// Workflows.CrossPoolCopyVm("https://poolA", "root", password, "https://poolB");
/// </code>
/// </example>
/// <remarks>
/// Copy a VM from one pool to another (Storage XenMotion copy). Open a session to each pool, get a
/// receiver token from the destination with host.migrate_receive, then VM.migrate_send with
/// copy=true on the source (which is left intact).
/// </remarks>
public static void CrossPoolCopyVm(string url, string user, string password, string destUrl,
    string vmName = "db-01", string destUser = null, string destPassword = null,
    string transferNetwork = null)
{
    var source = Connect(url, user, password);
    var dest = Connect(destUrl, destUser ?? user, destPassword ?? password);
    // Destination: choose a host, a network and an SR, then ask for a receiver token. The disks go to
    // the destination pool's default SR.
    var destPool = Pool.get_all(dest)[0];
    var destHost = Pool.get_master(dest, destPool).opaque_ref;
    var destSr = Pool.get_default_SR(dest, destPool).opaque_ref;
    var managementPif = Host.get_PIFs(dest, destHost).First(pif => PIF.get_management(dest, pif.opaque_ref));
    var destManagementNetwork = PIF.get_network(dest, managementPif.opaque_ref).opaque_ref;
    string migrationNetwork;
    if (transferNetwork != null)
    {
        migrationNetwork = Network.get_all_records(dest)
            .First(kv => kv.Value.name_label == transferNetwork).Key.opaque_ref;
    }
    else
    {
        // For performance, production use should carry migration traffic over a dedicated network
        // rather than the management network - pass transferNetwork with the name of one.
        migrationNetwork = destManagementNetwork;
    }
    var receiver = Host.migrate_receive(dest, destHost, migrationNetwork, new Dictionary<string, string>());

    // Source: map every disk to the destination SR and every NIC to the destination pool's
    // management network (the VM's guest-visible NICs, independent of the migration transfer),
    // then send with copy=true.
    var vm = VmByName(source, vmName);
    var vdiMap = new Dictionary<XenRef<VDI>, XenRef<SR>>();
    foreach (var vbdRef in VM.get_VBDs(source, vm))
    {
        if (VBD.get_type(source, vbdRef.opaque_ref) != vbd_type.Disk) continue;
        var vdi = VBD.get_VDI(source, vbdRef.opaque_ref);
        if (vdi.opaque_ref != "OpaqueRef:NULL") vdiMap[vdi] = new XenRef<SR>(destSr);
    }
    var vifMap = new Dictionary<XenRef<VIF>, XenRef<Network>>();
    foreach (var vifRef in VM.get_VIFs(source, vm)) vifMap[vifRef] = new XenRef<Network>(destManagementNetwork);

    var options = new Dictionary<string, string> { ["copy"] = "true" };
    var copy = VM.migrate_send(source, vm, receiver, false, vdiMap, vifMap, options,
        new Dictionary<XenRef<VGPU>, XenRef<GPU_group>>());

    // Copy (not move): the source VM is still on the source pool.
    Console.WriteLine($"Sent '{vmName}' to the destination pool (copy); source still present: " +
                      $"{VmByName(source, vmName) == vm}");
    // The result is the new VM's ref on the DESTINATION pool - use the destination session to read it.
    Console.WriteLine($"  the copy on the destination: {VM.get_name_label(dest, copy)} ({VM.get_uuid(dest, copy)})");

    // Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
    DestroyVmAndDisks(dest, copy.opaque_ref);
    Console.WriteLine("OK: cross-pool-copy-vm");
    source.logout();
    dest.logout();
}
```

<details><summary>Sample output</summary>

```text
Sent 'db-01' to the destination pool (copy); source still present: True
  the copy on the destination: db-01 (00000001-0000-0000-080a-000000000000)
OK: cross-pool-copy-vm
```

</details>

## Python

Source: [`python/virtual_machines/cross_pool_copy_vm.py`](../../python/virtual_machines/cross_pool_copy_vm.py)

```python
"""Cross-pool copy a VM.

Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the
destination, then send a copy of the VM from the source. Takes the destination pool's URL as an
extra argument after the password.

Run it::

    cross_pool_copy_vm("https://poolA", "root", password, "https://poolB")
"""

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name


def cross_pool_copy_vm(url, username, password, dest_url, vm_name="db-01",
                       dest_username=None, dest_password=None, transfer_network=None):
    """Copy a VM from one pool to another (Storage XenMotion copy): get a receiver token from the
    destination with host.migrate_receive, then VM.migrate_send with copy=true on the source.

    transfer_network, if given, is the name of a network on the destination pool to carry the
    migration traffic (the VM's disks and memory) - pass the name of a dedicated migration network."""
    source = connect(url, username, password)
    dest = connect(dest_url, dest_username or username, dest_password or password)
    # Destination: choose a host, network and SR, then ask for a receiver token. The disks go to
    # the destination pool's default SR.
    dest_pool = dest.xenapi.pool.get_all()[0]
    dest_host = dest.xenapi.pool.get_master(dest_pool)
    dest_sr = dest.xenapi.pool.get_default_SR(dest_pool)
    dest_management_network = next(dest.xenapi.PIF.get_network(pif)
                                   for pif in dest.xenapi.host.get_PIFs(dest_host)
                                   if dest.xenapi.PIF.get_management(pif))
    if transfer_network:
        migration_network = next(net for net in dest.xenapi.network.get_all()
                                 if dest.xenapi.network.get_name_label(net) == transfer_network)
    else:
        # For performance, production use should carry migration traffic over a dedicated network
        # rather than the management network - pass transfer_network with the name of one.
        migration_network = dest_management_network
    receiver = dest.xenapi.host.migrate_receive(dest_host, migration_network, {})

    # Source: map every disk to the destination SR and every NIC to the destination pool's
    # management network (the VM's guest-visible NICs, independent of the migration transfer),
    # then send with copy=true (source VM is left intact).
    vm = vm_by_name(source, vm_name)
    vdi_map = {}
    for vbd in source.xenapi.VM.get_VBDs(vm):
        if source.xenapi.VBD.get_type(vbd) != "Disk":
            continue
        vdi = source.xenapi.VBD.get_VDI(vbd)
        if vdi != "OpaqueRef:NULL":
            vdi_map[vdi] = dest_sr
    vif_map = {vif: dest_management_network for vif in source.xenapi.VM.get_VIFs(vm)}

    copy = source.xenapi.VM.migrate_send(vm, receiver, False, vdi_map, vif_map, {"copy": "true"}, {})
    print("Sent '%s' to the destination pool (copy); source still present: %s"
          % (vm_name, vm_by_name(source, vm_name) == vm))
    # The result is the new VM's ref on the DESTINATION pool - use the destination session to read it.
    print("  the copy on the destination: %s (%s)"
          % (dest.xenapi.VM.get_name_label(copy), dest.xenapi.VM.get_uuid(copy)))

    # Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
    destroy_vm_and_disks(dest, copy)
    print("OK: cross-pool-copy-vm")
    source.xenapi.session.logout()
    dest.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Sent 'db-01' to the destination pool (copy); source still present: True
  the copy on the destination: db-01 (00000001-0000-0000-ea09-000000000000)
OK: cross-pool-copy-vm
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/CrossPoolCopyVm.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/CrossPoolCopyVm.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.GPUGroup;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.PIF;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VGPU;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

import java.util.HashMap;
import java.util.Map;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CrossPoolCopyVm {
    private CrossPoolCopyVm() {
    }

    /**
     * Cross-pool copy a VM.
     *
     * <p>Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the
     * destination, then send a copy of the VM from the source. Takes the destination pool's URL as an
     * extra argument after the password.
     *
     * <p>Copy a VM from one pool to another (Storage XenMotion copy): get a receiver token from the
     * destination with host.migrate_receive, then VM.migrate_send with copy=true on the source.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CrossPoolCopyVm.run("https://poolA", "root", password, "https://poolB", "db-01", null, null, null);
     * }</pre>
     */
    public static void run(String url, String user, String password, String destUrl,
            String vmName, String destUser, String destPassword) throws Exception {
        run(url, user, password, destUrl, vmName, destUser, destPassword, null);
    }

    /**
     * As {@link #run(String, String, String, String, String, String, String)}, but carrying the
     * migration traffic over the named destination network instead of its management network.
     */
    public static void run(String url, String user, String password, String destUrl,
            String vmName, String destUser, String destPassword, String transferNetwork) throws Exception {
        Connection source = connect(url, user, password);
        Connection dest = connect(destUrl, destUser != null ? destUser : user,
                destPassword != null ? destPassword : password);
        // Destination: choose a host, network and SR, then ask for a receiver token. The disks go to
        // the destination pool's default SR.
        Pool destPool = Pool.getAll(dest).iterator().next();
        Host destHost = destPool.getMaster(dest);
        SR destSr = destPool.getDefaultSR(dest);
        Network destManagementNetwork = null;
        for (PIF pif : destHost.getPIFs(dest))
            if (pif.getManagement(dest)) destManagementNetwork = pif.getNetwork(dest);
        Network migrationNetwork;
        if (transferNetwork != null) {
            migrationNetwork = null;
            for (Network net : Network.getAll(dest))
                if (net.getNameLabel(dest).equals(transferNetwork)) migrationNetwork = net;
        } else {
            // For performance, production use should carry migration traffic over a dedicated network
            // rather than the management network - pass transferNetwork with the name of one.
            migrationNetwork = destManagementNetwork;
        }
        Map<String, String> receiver = destHost.migrateReceive(dest, migrationNetwork, new HashMap<>());

        // Source: map every disk to the destination SR and every NIC to the destination pool's
        // management network (the VM's guest-visible NICs, independent of the migration transfer),
        // then send with copy=true (the source VM is left intact).
        VM vm = vmByName(source, vmName);
        Map<VDI, SR> vdiMap = new HashMap<>();
        for (VBD vbd : vm.getVBDs(source))
            if (vbd.getType(source) == Types.VbdType.DISK) vdiMap.put(vbd.getVDI(source), destSr);
        Map<VIF, Network> vifMap = new HashMap<>();
        for (VIF vif : vm.getVIFs(source)) vifMap.put(vif, destManagementNetwork);

        Map<String, String> options = new HashMap<>();
        options.put("copy", "true");
        VM copy = vm.migrateSend(source, receiver, false, vdiMap, vifMap, options,
                new HashMap<VGPU, GPUGroup>());
        System.out.println("Sent '" + vmName + "' to the destination pool (copy); source still present: "
                + vmByName(source, vmName).equals(vm));
        // The result is the new VM's ref on the DESTINATION pool - use the destination session to read it.
        System.out.println("  the copy on the destination: " + copy.getNameLabel(dest) + " ("
                + copy.getUuid(dest) + ")");

        // Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
        destroyVmAndDisks(dest, copy);
        System.out.println("OK: cross-pool-copy-vm");
        Session.logout(source);
        Session.logout(dest);
    }
}
```

<details><summary>Sample output</summary>

```text
Sent 'db-01' to the destination pool (copy); source still present: true
  the copy on the destination: db-01 (00000001-0000-0000-110a-000000000000)
OK: cross-pool-copy-vm
```

</details>

## Go

Source: [`go/cross_pool_copy_vm.go`](../../go/cross_pool_copy_vm.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// crossPoolCopyVM - Cross-pool copy a VM.
//
// Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the
// destination, then send a copy of the VM from the source. Takes the destination pool's URL as an
// extra argument after the password.
//
// Copy a VM from one pool to another (Storage XenMotion copy): get a receiver token from the
// destination with host.migrate_receive, then VM.migrate_send with copy=true on the source.
//
// Run it:
//
//	crossPoolCopyVM("https://poolA", "root", password, "https://poolB", "db-01", "", "")
func crossPoolCopyVM(url, user, password, destURL, vmName, destUser, destPassword string) {
	crossPoolCopyVMOverNetwork(url, user, password, destURL, vmName, destUser, destPassword, "")
}

// crossPoolCopyVMOverNetwork is crossPoolCopyVM, but carrying the migration traffic over the
// destination network named by transferNetwork instead of the destination's management network;
// an empty transferNetwork falls back to the management network.
func crossPoolCopyVMOverNetwork(url, user, password, destURL, vmName, destUser, destPassword, transferNetwork string) {
	source := connect(url, user, password)
	if destUser == "" {
		destUser, destPassword = user, password
	}
	dest := connect(destURL, destUser, destPassword)
	// Destination: choose a host, network and SR, then ask for a receiver token. The disks go to
	// the destination pool's default SR.
	destPools, err := xenapi.Pool.GetAll(dest)
	check(err)
	destHost, err := xenapi.Pool.GetMaster(dest, destPools[0])
	check(err)
	destSr, err := xenapi.Pool.GetDefaultSR(dest, destPools[0])
	check(err)
	pifs, err := xenapi.Host.GetPIFs(dest, destHost)
	check(err)
	var destManagementNetwork xenapi.NetworkRef
	for _, pif := range pifs {
		if management, _ := xenapi.PIF.GetManagement(dest, pif); management {
			destManagementNetwork, err = xenapi.PIF.GetNetwork(dest, pif)
			check(err)
		}
	}
	migrationNetwork := destManagementNetwork
	if transferNetwork != "" {
		nets, err := xenapi.Network.GetAllRecords(dest)
		check(err)
		for ref, net := range nets {
			if net.NameLabel == transferNetwork {
				migrationNetwork = ref
			}
		}
	}
	// For performance, production use should carry migration traffic over a dedicated network
	// rather than the management network - pass transferNetwork with the name of one.
	receiver, err := xenapi.Host.MigrateReceive(dest, destHost, migrationNetwork, map[string]string{})
	check(err)

	// Source: map every disk to the destination SR and every NIC to the destination pool's
	// management network (the VM's guest-visible NICs, independent of the migration transfer),
	// then send with copy=true (the source VM is left intact).
	vm := vmByName(source, vmName)
	vbds, _ := xenapi.VM.GetVBDs(source, vm)
	vdiMap := map[xenapi.VDIRef]xenapi.SRRef{}
	for _, vbd := range vbds {
		if t, _ := xenapi.VBD.GetType(source, vbd); t != xenapi.VbdTypeDisk {
			continue
		}
		vdi, _ := xenapi.VBD.GetVDI(source, vbd)
		vdiMap[vdi] = destSr
	}
	vifs, _ := xenapi.VM.GetVIFs(source, vm)
	vifMap := map[xenapi.VIFRef]xenapi.NetworkRef{}
	for _, vif := range vifs {
		vifMap[vif] = destManagementNetwork
	}

	// MigrateSend8 is the 8-argument form every pool version accepts; MigrateSend itself takes newer
	// arguments that older hosts reject.
	copied, err := xenapi.VM.MigrateSend8(source, vm, receiver, false, vdiMap, vifMap,
		map[string]string{"copy": "true"}, map[xenapi.VGPURef]xenapi.GPUGroupRef{})
	check(err)
	fmt.Printf("Sent '%s' to the destination pool (copy); source still present: %v\n",
		vmName, vmByName(source, vmName) == vm)
	// The result is the new VM's ref on the DESTINATION pool - use the destination session to read it.
	copyName, err := xenapi.VM.GetNameLabel(dest, copied)
	check(err)
	copyUUID, err := xenapi.VM.GetUUID(dest, copied)
	check(err)
	fmt.Printf("  the copy on the destination: %s (%s)\n", copyName, copyUUID)

	// Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
	destroyVMAndDisks(dest, copied)
	fmt.Println("OK: cross-pool-copy-vm")
	dest.Logout()
	source.Logout()
}
```

<details><summary>Sample output</summary>

```text
Sent 'db-01' to the destination pool (copy); source still present: true
  the copy on the destination: db-01 (00000001-0000-0000-fe09-000000000000)
OK: cross-pool-copy-vm
```

</details>

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-CrossPoolCopyVm.ps1`](../../powershell/VirtualMachines/Invoke-CrossPoolCopyVm.ps1)

```powershell
function Invoke-CrossPoolCopyVm {
    <#
    .SYNOPSIS
        Cross-pool copy a VM.
    .DESCRIPTION
        Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the
        destination, then send a copy of the VM from the source. Takes the destination pool's URL as an
        extra argument after the password.
    .EXAMPLE
        Invoke-CrossPoolCopyVm -Url https://poolA -UserName root -Password $password -DestUrl https://poolB `
    .EXAMPLE
        [-DestUserName root -DestPassword $destPassword] [-VmName db-01]
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$DestUrl,
        [string]$VmName = "db-01",
        # The destination pool's credentials, if they differ from the source's.
        [string]$DestUserName = $UserName,
        [string]$DestPassword = $Password,
        # A network on the destination pool to carry the migration traffic - pass the name of a
        # dedicated migration network. Defaults to the destination's management network.
        [string]$TransferNetwork
    )
    # Two pools, so two sessions. Every cmdlet takes -SessionOpaqueRef, so we drive each pool explicitly
    # (Connect-Example sets a default session too, but being explicit keeps the two pools apart).
    $source = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $dest = Connect-Example -Url $DestUrl -UserName $DestUserName -Password $DestPassword
    $srcRef = $source.opaque_ref
    $dstRef = $dest.opaque_ref

    # Destination: choose a host, network and SR, then ask for a receiver token (a string->string map).
    # The disks go to the destination pool's default SR.
    $destPool = Get-XenPool -SessionOpaqueRef $dstRef | Select-Object -First 1
    $destHost = Get-XenHost -SessionOpaqueRef $dstRef -Ref $destPool.master.opaque_ref
    $destSr = Get-XenSR -SessionOpaqueRef $dstRef -Ref $destPool.default_SR.opaque_ref
    $managementPif = Get-XenPIF -SessionOpaqueRef $dstRef |
        Where-Object { $_.management -and $_.host.opaque_ref -eq $destHost.opaque_ref } | Select-Object -First 1
    $destManagementNet = Get-XenNetwork -SessionOpaqueRef $dstRef -Ref $managementPif.network.opaque_ref
    if ($TransferNetwork) {
        $migrationNet = Get-XenNetwork -SessionOpaqueRef $dstRef -Name $TransferNetwork | Select-Object -First 1
        if (-not $migrationNet) { throw "No network named '$TransferNetwork' was found on the destination pool." }
    }
    else {
        # For performance, production use should carry migration traffic over a dedicated network
        # rather than the management network - pass -TransferNetwork with the name of one.
        $migrationNet = $destManagementNet
    }
    $receiver = $destHost | Invoke-XenHost -SessionOpaqueRef $dstRef -XenAction MigrateReceive `
        -Network $migrationNet -Options @{} -PassThru

    # Source: find the VM, then map every disk to the destination SR and every NIC to the destination
    # pool's management network (the VM's guest-visible NICs, independent of the migration transfer).
    # migrate_send's maps are strongly-typed (source XenRef -> destination XenRef) dictionaries, so build
    # them as such; ConvertTo-XenRef turns each destination object into the typed ref the values need
    # (the source refs come straight off the VM's .VBDs/.VIFs).
    $vm = Get-XenVM -SessionOpaqueRef $srcRef -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1

    $vdiMap = New-Object 'System.Collections.Generic.Dictionary[XenAPI.XenRef[XenAPI.VDI], XenAPI.XenRef[XenAPI.SR]]'
    foreach ($vbdRef in $vm.VBDs) {
        $vbd = Get-XenVBD -SessionOpaqueRef $srcRef -Ref $vbdRef.opaque_ref
        if ($vbd.type -eq 'Disk' -and $vbd.VDI.opaque_ref -ne 'OpaqueRef:NULL') {
            $vdiMap[$vbd.VDI] = ConvertTo-XenRef -XenObject $destSr
        }
    }
    $vifMap = New-Object 'System.Collections.Generic.Dictionary[XenAPI.XenRef[XenAPI.VIF], XenAPI.XenRef[XenAPI.Network]]'
    foreach ($vifRef in $vm.VIFs) { $vifMap[$vifRef] = ConvertTo-XenRef -XenObject $destManagementNet }

    # Send with copy=true (the source VM is left intact). Dest/VdiMap/VifMap/VgpuMap are the migrate_send
    # action's parameters.
    # The VMs the destination already has, to tell the copy apart afterwards (never by name alone).
    $before = @(Get-XenVM -SessionOpaqueRef $dstRef | ForEach-Object { $_.opaque_ref })
    $vm | Invoke-XenVM -SessionOpaqueRef $srcRef -XenAction MigrateSend -Dest $receiver -Live $false `
        -VdiMap $vdiMap -VifMap $vifMap -Options @{ copy = "true" } -VgpuMap @{}

    $stillThere = [bool](Get-XenVM -SessionOpaqueRef $srcRef -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain })
    Write-Host "Sent '$VmName' to the destination pool (copy); source still present: $stillThere"

    # Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
    $copy = Get-XenVM -SessionOpaqueRef $dstRef | Where-Object { $_.opaque_ref -notin $before } |
        Select-Object -First 1
    if ($copy) {
        Write-Host "  the copy on the destination: $($copy.name_label) ($($copy.uuid))"
        $copyVdis = @($copy.VBDs | ForEach-Object { Get-XenVBD -SessionOpaqueRef $dstRef -Ref $_.opaque_ref } |
            Where-Object { $_.type -eq 'Disk' -and $_.VDI.opaque_ref -ne 'OpaqueRef:NULL' } |
            ForEach-Object { $_.VDI.opaque_ref })
        Remove-XenVM -SessionOpaqueRef $dstRef -Ref $copy.opaque_ref
        $copyVdis | ForEach-Object { Remove-XenVDI -SessionOpaqueRef $dstRef -Ref $_ }
    }
    else {
        # No new VM on the destination: the copy did not arrive, so there is nothing to tidy up.
        Write-Host "  the copy on the destination: not found (nothing to tidy up)"
    }
    Write-Host "OK: cross-pool-copy-vm"
    $source | Disconnect-XenServer
    $dest | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Sent 'db-01' to the destination pool (copy); source still present: True
  the copy on the destination: db-01 (00000001-0000-0000-080a-000000000000)
OK: cross-pool-copy-vm
```

</details>

## xe CLI

Source: [`cli/virtual-machines/cross-pool-copy-vm.sh`](../../cli/virtual-machines/cross-pool-copy-vm.sh)

```bash
# Cross-pool copy a VM.
#
# Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the destination,
# then send a copy of the VM from the source. Takes the destination pool's URL as an extra argument after the
# password.
#
# Run it:
#   ./workflows.sh cross-pool-copy-vm https://xenserver root "$password" https://other-pool
#
# Optional key=value arguments (default):
#   transfer_network ("" - falls back to the destination's management network)

cross_pool_copy_vm() {
    # Copy a VM to another pool (Storage XenMotion copy). Real xe does the whole cross-pool dance
    # itself given the destination master's address + credentials; copy=true leaves the source intact.
    local dest_hp dest_master dest_net transfer_network v
    local -a dest_opts vif_map migrate_opts
    dest_hp=${desturl#*://}; dest_hp=${dest_hp%%/*}
    dest_host=${dest_hp%%:*}
    dest_opts=()
    if [ "$dest_hp" != "$dest_host" ] && [ "${dest_hp##*:}" != 443 ]; then dest_opts=(-p $((${dest_hp##*:} + 1))); fi
    case "${XE_EXE:-xe}" in *.exe | *.EXE) dest_opts+=(-no-warn-new-certificates -no-warn-certificates) ;; esac
    # Like xe() (connection.sh), but for the destination pool - and like it, pass a failure's output on to
    # stderr: captured by $(...), it would otherwise vanish and set -e would stop the script silently.
    xe_dest() {
        local out rc=0
        out=$(command "${XE_EXE:-xe}" -s "$dest_host" "${dest_opts[@]}" -u "$destuser" -pw "$destpass" "$@") || rc=$?
        if [ $rc -ne 0 ]; then [ -z "$out" ] || printf '%s\n' "$out" >&2; return $rc; fi
        [ -z "$out" ] || printf '%s\n' "$out"
    }
    vm=$(vm_uuid "$copy_vm")
    # Map every NIC to the destination coordinator's management network, one both pools can certainly
    # reach. Left unmapped, a real pool refuses the VIF ("not mapped to a destination Network") unless it
    # happens to find a same-named network there.
    dest_master=$(xe_dest pool-param-get uuid=$(xe_dest pool-list --minimal) param-name=master)
    dest_net=$(xe_dest pif-list host-uuid=$dest_master management=true params=network-uuid --minimal)
    vif_map=()
    for v in $(each_csv "$(xe vif-list vm-uuid=$vm --minimal)"); do vif_map+=("vif:$v=$dest_net"); done
    # And every disk to the destination pool's default SR. Left unmapped, xe picks an SR itself - on a real
    # pool a small shared one it happened to prefer, which ran out of space (SR_BACKEND_FAILURE_44).
    local dest_sr vbd vdi_map=()
    dest_sr=$(xe_dest pool-param-get uuid=$(xe_dest pool-list --minimal) param-name=default-SR)
    for vbd in $(each_csv "$(xe vbd-list vm-uuid=$vm type=Disk --minimal)"); do
        vdi=$(xe vbd-param-get uuid=$vbd param-name=vdi-uuid)
        [[ $vdi == *-* ]] && vdi_map+=("vdi:$vdi=$dest_sr")
    done
    # The migration traffic itself travels over remote-network if given, or (as here, left unset) xe
    # falls back to the destination's management network. For performance, production use should use a
    # dedicated migration network instead - pass transfer_network=<name|uuid> to set remote-network.
    transfer_network=$(param transfer_network "")
    migrate_opts=()
    [ -n "$transfer_network" ] && migrate_opts+=(remote-network="$transfer_network")

    # The VMs the destination already has, to tell the copy apart afterwards (never by name alone).
    local before copy
    before=",$(xe_dest vm-list is-control-domain=false --minimal),"
    xe vm-migrate uuid=$vm remote-master=$dest_host remote-username=$destuser remote-password=$destpass copy=true \
        "${migrate_opts[@]}" "${vif_map[@]}" "${vdi_map[@]}"
    still=$([ -n "$(vm_uuid "$copy_vm")" ] && echo True || echo False)
    echo "Sent '$copy_vm' to $dest_host (copy); source still present: $still"

    # Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
    copy=""
    for v in $(each_csv "$(xe_dest vm-list is-control-domain=false --minimal)"); do
        [[ $before == *",$v,"* ]] || { copy=$v; break; }
    done
    if [ -n "$copy" ]; then
        echo "  the copy on the destination: $(xe_dest vm-param-get uuid=$copy param-name=name-label) ($copy)"
        xe_dest vm-uninstall uuid=$copy force=true
    else
        # No new VM on the destination: the copy did not arrive, so there is nothing to tidy up.
        echo "  the copy on the destination: not found (nothing to tidy up)"
    fi
    echo "OK: cross-pool-copy-vm"
}
```

<details><summary>Sample output</summary>

```text
Sent 'db-01' to localhost (copy); source still present: True
  the copy on the destination: not found (nothing to tidy up)
OK: cross-pool-copy-vm
```

</details>
