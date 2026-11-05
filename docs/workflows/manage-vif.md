<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage network interfaces

Attach a virtual network interface to a VM and remove it again.

Workflow `manage-vif`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Networking/ManageVif.cs`](../../csharp/Networking/ManageVif.cs)

```csharp
/// <summary>
/// Attach a virtual network interface to a VM and remove it again.
/// </summary>
/// <example>
/// <code>
/// Workflows.ManageVif("https://xenserver", "root", password, "Rocky Linux 8");
/// </code>
/// </example>
public static void ManageVif(string url, string user, string password,
    string templateName, string newVmName = "sdk-example-vif")
{
    var session = Connect(url, user, password);
    var vm = VM.clone(session, TemplateByName(session, templateName), newVmName).opaque_ref;
    Provision(session, vm);
    var netRef = Network.get_all(session)[0].opaque_ref;
    var device = VM.get_allowed_VIF_devices(session, vm)[0];

    var vif = VIF.create(session, new VIF
    {
        VM = new XenRef<VM>(vm),
        network = new XenRef<Network>(netRef),
        device = device,
        MAC = "",
        MTU = 1500,
        other_config = new Dictionary<string, string>(),
        qos_algorithm_type = "",
        qos_algorithm_params = new Dictionary<string, string>(),
    }).opaque_ref;
    Console.WriteLine($"Attached a VIF on device {device}; VM now has {VM.get_VIFs(session, vm).Count} NIC(s)");

    VIF.destroy(session, vif);
    DestroyVmAndDisks(session, vm);
    Console.WriteLine("OK: manage-vif");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Attached a VIF on device 0; VM now has 1 NIC(s)
OK: manage-vif
```

</details>

## Python

Source: [`python/networking/manage_vif.py`](../../python/networking/manage_vif.py)

```python
"""Manage network interfaces.

Attach a virtual network interface to a VM and remove it again.

Run it::

    manage_vif("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, template_by_name


def manage_vif(url, username, password, template_name, new_vm_name="sdk-example-vif"):
    """Provision a throwaway VM, attach a VIF to the first network, then tear it all down."""
    session = connect(url, username, password)
    vm = session.xenapi.VM.clone(template_by_name(session, template_name), new_vm_name)
    provision(session, vm)
    net_ref = session.xenapi.network.get_all()[0]
    device = session.xenapi.VM.get_allowed_VIF_devices(vm)[0]

    vif = session.xenapi.VIF.create({
        "VM": vm, "network": net_ref, "device": device, "MAC": "",
        "MTU": "1500", "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("Attached a VIF on device %s; VM now has %d NIC(s)"
          % (device, len(session.xenapi.VM.get_VIFs(vm))))

    session.xenapi.VIF.destroy(vif)
    destroy_vm_and_disks(session, vm)
    print("OK: manage-vif")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Attached a VIF on device 0; VM now has 1 NIC(s)
OK: manage-vif
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/networking/ManageVif.java`](../../java/src/main/java/com/xenserver/samples/networking/ManageVif.java)

```java
package com.xenserver.samples.networking;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class ManageVif {
    private ManageVif() {
    }

    /**
     * Manage network interfaces.
     *
     * <p>Attach a virtual network interface to a VM and remove it again.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageVif.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vif");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm);
        Network net = Network.getAll(conn).iterator().next();
        String device = vm.getAllowedVIFDevices(conn).iterator().next();

        VIF.Record vifRec = new VIF.Record();
        vifRec.VM = vm;
        vifRec.network = net;
        vifRec.device = device;
        vifRec.MAC = "";
        vifRec.MTU = 1500L;
        vifRec.otherConfig = new java.util.HashMap<>();
        vifRec.qosAlgorithmType = "";
        vifRec.qosAlgorithmParams = new java.util.HashMap<>();
        // Left unset, the binding's Record defaults these two enums to its own UNRECOGNIZED sentinel,
        // which released xapi rejects outright rather than treating as "no IP configured". Say so
        // explicitly.
        vifRec.ipv4ConfigurationMode = Types.VifIpv4ConfigurationMode.NONE;
        vifRec.ipv6ConfigurationMode = Types.VifIpv6ConfigurationMode.NONE;
        VIF vif = VIF.create(conn, vifRec);
        System.out.println("Attached a VIF on device " + device + "; VM now has "
                + vm.getVIFs(conn).size() + " NIC(s)");

        vif.destroy(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: manage-vif");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Attached a VIF on device 0; VM now has 1 NIC(s)
OK: manage-vif
```

</details>

## Go

Source: [`go/manage_vif.go`](../../go/manage_vif.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// manageVif - Manage network interfaces.
//
// Attach a virtual network interface to a VM and remove it again.
//
// Run it:
//
//	manageVif("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vif")
func manageVif(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	vm, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vm)
	nets, err := xenapi.Network.GetAll(session)
	check(err)
	netRef := nets[0]
	devices, err := xenapi.VM.GetAllowedVIFDevices(session, vm)
	check(err)
	device := devices[0]

	// A Go record sends every field, enums included, and a real host rejects an empty enum value
	// (INTERNAL_ERROR "Unknown tag/contents"), so set the enums to the defaults xapi applies when
	// they are left out.
	vif, err := xenapi.VIF.Create(session, xenapi.VIFRecord{
		VM: vm, Network: netRef, Device: device, MAC: "", MTU: 1500,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
		LockingMode:           xenapi.VifLockingModeNetworkDefault,
		Ipv4ConfigurationMode: xenapi.VifIpv4ConfigurationModeNone,
		Ipv6ConfigurationMode: xenapi.VifIpv6ConfigurationModeNone,
	})
	check(err)
	vifs, _ := xenapi.VM.GetVIFs(session, vm)
	fmt.Printf("Attached a VIF on device %s; VM now has %d NIC(s)\n", device, len(vifs))

	check(xenapi.VIF.Destroy(session, vif))
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: manage-vif")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Attached a VIF on device 0; VM now has 1 NIC(s)
OK: manage-vif
```

</details>

## PowerShell

Source: [`powershell/Networking/Invoke-ManageVif.ps1`](../../powershell/Networking/Invoke-ManageVif.ps1)

```powershell
function Invoke-ManageVif {
    <#
    .SYNOPSIS
        Manage network interfaces.
    .DESCRIPTION
        Attach a virtual network interface to a VM and remove it again.
    .EXAMPLE
        Invoke-ManageVif -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-vif"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm.opaque_ref
    $ref = $vm.opaque_ref

    $net = Get-XenNetwork | Select-Object -First 1
    $device = (Get-XenVMProperty -Ref $ref -XenProperty AllowedVIFDevices)[0]

    $vif = New-XenVIF -VM (Get-XenVM -Ref $ref) -Network $net -Device $device -MAC "" -MTU 1500 -PassThru
    Write-Host "Attached a VIF on device $device; VM now has $(@((Get-XenVM -Ref $ref).VIFs).Count) NIC(s)"

    $vif | Remove-XenVIF
    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "OK: manage-vif"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Attached a VIF on device 0; VM now has 1 NIC(s)
OK: manage-vif
```

</details>

## xe CLI

Source: [`cli/networking/manage-vif.sh`](../../cli/networking/manage-vif.sh)

```bash
# Manage network interfaces.
#
# Attach a virtual network interface to a VM and remove it again.
#
# Run it:
#   ./workflows.sh manage-vif https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

manage_vif() {
    local template=$(param template_name "Rocky Linux 8") device
    vm=$(xe vm-install template="$template" new-name-label=xe-example-vif)
    net=$(first_csv "$(xe network-list --minimal)")
    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=allowed-VIF-devices)")")
    vif=$(xe vif-create vm-uuid=$vm network-uuid=$net device=$device)
    echo "Attached a VIF; VM now has $(count_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=VIFs)")") NIC(s)"
    xe vif-destroy uuid=$vif
    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it owns (vm-destroy
    # would leave the disks behind).
    xe vm-uninstall uuid=$vm force=true
    echo "OK: manage-vif"
}
```

<details><summary>Example output</summary>

```text
Attached a VIF; VM now has 0 NIC(s)
OK: manage-vif
```

</details>
