<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create a NIC bond

Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond back, then dissolve it.

Workflow `create-bond`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Networking/CreateBond.cs`](../../csharp/Networking/CreateBond.cs)

```csharp
/// <summary>
/// Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond
/// back, then dissolve it.
/// </summary>
/// <example>
/// <code>
/// Workflows.CreateBond("https://xenserver", "root", password);
/// </code>
/// </example>
public static void CreateBond(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var host = Host.get_all(session)[0].opaque_ref;

    // Pick up any NIC racked since the host booted. Cheap, and without it a card added a moment ago
    // is not there to bond.
    PIF.scan(session, host);

    // Spare NICs only. A bond that includes the management interface moves the management address
    // onto the bond master — on a real host that is how you lose the connection you are working over.
    var spares = PIF.get_all_records(session)
        .Where(p => p.Value.host.opaque_ref == host && !p.Value.management && p.Value.physical)
        .Take(2).Select(p => p.Key).ToList();
    if (spares.Count < 2)
        throw new Exception($"{Host.get_name_label(session, host)} has {spares.Count} spare NIC(s); " +
                             "a bond needs two that aren't the management interface");
    Console.WriteLine($"Bonding:      {string.Join(", ", spares.Select(p => PIF.get_device(session, p.opaque_ref)))}");

    // The bond needs a network to sit on.
    var network = Network.create(session, new Network
    {
        name_label = "sdk-example-bond",
        name_description = "Created by the SDK example",
        other_config = new Dictionary<string, string>(),
    });

    var bond = Bond.create(session, network.opaque_ref, spares, "", bond_mode.balance_slb);
    var master = Bond.get_master(session, bond.opaque_ref);
    Console.WriteLine($"Bond master:  {PIF.get_device(session, master.opaque_ref)}");
    Console.WriteLine($"Mode:         {Bond.get_mode(session, bond.opaque_ref)}");

    // Dissolving returns the NICs to standalone use (and moves management back, had it been bonded).
    Bond.destroy(session, bond.opaque_ref);
    Network.destroy(session, network.opaque_ref);
    Console.WriteLine($"Bonds left:   {Bond.get_all(session).Count}");
    Console.WriteLine("OK: create-bond");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Bonding:      eth1, eth2
Bond master:  bond0
Mode:         balance_slb
Bonds left:   0
OK: create-bond
```

</details>

## Python

Source: [`python/networking/create_bond.py`](../../python/networking/create_bond.py)

```python
"""Create a NIC bond.

Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond
back, then dissolve it.

Run it::

    create_bond("https://xenserver", "root", password)
"""

from connection import connect


def create_bond(url, username, password):
    """Bond two spare NICs onto a new network, then dissolve the bond."""
    session = connect(url, username, password)
    x = session.xenapi
    host = x.host.get_all()[0]

    # Pick up any NIC racked since the host booted. Cheap, and without it a card added a moment ago is
    # not there to bond.
    x.PIF.scan(host)

    # Spare NICs only. A bond that includes the management interface moves the management address onto
    # the bond master — on a real host that is how you lose the connection you are working over.
    spares = [ref for ref, pif in x.PIF.get_all_records().items()
              if pif["host"] == host and not pif["management"] and pif["physical"]][:2]
    if len(spares) < 2:
        raise RuntimeError("%s has %d spare NIC(s); a bond needs two that aren't the management interface"
                           % (x.host.get_name_label(host), len(spares)))
    print("Bonding:      " + ", ".join(x.PIF.get_device(p) for p in spares))

    # The bond needs a network to sit on.
    network = x.network.create({
        "name_label": "sdk-example-bond",
        "name_description": "Created by the SDK example",
        "other_config": {},
    })

    bond = x.Bond.create(network, spares, "", "balance-slb")
    print(f"Bond master:  {x.PIF.get_device(x.Bond.get_master(bond))}")
    print(f"Mode:         {x.Bond.get_mode(bond)}")

    # Dissolving returns the NICs to standalone use (and moves management back, had it been bonded).
    x.Bond.destroy(bond)
    x.network.destroy(network)
    print(f"Bonds left:   {len(x.Bond.get_all())}")
    print("OK: create-bond")
    x.session.logout()
```

<details><summary>Sample output</summary>

```text
Bonding:      eth1, eth2
Bond master:  bond0
Mode:         balance-slb
Bonds left:   0
OK: create-bond
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/networking/CreateBond.java`](../../java/src/main/java/com/xenserver/samples/networking/CreateBond.java)

```java
package com.xenserver.samples.networking;

import com.xensource.xenapi.Bond;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.PIF;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

public final class CreateBond {
    private CreateBond() {
    }

    /**
     * Create a NIC bond.
     *
     * <p>Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond
     * back, then dissolve it.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateBond.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Host xenHost = Host.getAll(conn).iterator().next();

            // Pick up any NIC racked since the host booted. Cheap, and without it a card added a moment
            // ago is not there to bond.
            PIF.scan(conn, xenHost);

            // Spare NICs only. A bond that includes the management interface moves the management
            // address onto the bond master — on a real host that is how you lose your connection.
            Set<PIF> spares = new LinkedHashSet<PIF>();
            for (Map.Entry<PIF, PIF.Record> e : PIF.getAllRecords(conn).entrySet()) {
                if (e.getValue().host.equals(xenHost) && !e.getValue().management && e.getValue().physical
                        && spares.size() < 2) {
                    spares.add(e.getKey());
                }
            }
            if (spares.size() < 2)
                throw new RuntimeException(xenHost.getNameLabel(conn) + " has " + spares.size()
                        + " spare NIC(s); a bond needs two that aren't the management interface");
            StringBuilder devices = new StringBuilder();
            for (PIF p : spares) devices.append(devices.length() > 0 ? ", " : "").append(p.getDevice(conn));
            System.out.println("Bonding:      " + devices);

            // The bond needs a network to sit on.
            Network.Record netSpec = new Network.Record();
            netSpec.nameLabel = "sdk-example-bond";
            netSpec.nameDescription = "Created by the SDK example";
            netSpec.otherConfig = new HashMap<String, String>();
            netSpec.managed = true;   // as in createNetwork: unset would send false (NETWORK_UNMANAGED)
            Network network = Network.create(conn, netSpec);

            Bond bond = Bond.create(conn, network, spares, "", Types.BondMode.BALANCE_SLB);
            System.out.println("Bond master:  " + bond.getMaster(conn).getDevice(conn));
            System.out.println("Mode:         " + bond.getMode(conn));

            bond.destroy(conn);
            network.destroy(conn);
            System.out.println("Bonds left:   " + Bond.getAll(conn).size());
            System.out.println("OK: create-bond");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Sample output</summary>

```text
Bonding:      eth1, eth2
Bond master:  bond0
Mode:         balance-slb
Bonds left:   0
OK: create-bond
```

</details>

## Go

Source: [`go/create_bond.go`](../../go/create_bond.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// createBond - Create a NIC bond.
//
// Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond
// back, then dissolve it.
func createBond(url, user, password string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)

	// Pick up any NIC racked since the host booted. Cheap, and without it a card added a moment
	// ago is not there to bond.
	check(xenapi.PIF.Scan(session, hosts[0]))

	// Spare NICs only. A bond that includes the management interface moves the management address onto
	// the bond master — on a real host that is how you lose the connection you are working over.
	pifs, err := xenapi.PIF.GetAllRecords(session)
	check(err)
	var spares []xenapi.PIFRef
	var devices []string
	for ref, pif := range pifs {
		if pif.Host == hosts[0] && !pif.Management && pif.Physical && len(spares) < 2 {
			spares = append(spares, ref)
			devices = append(devices, pif.Device)
		}
	}
	if len(spares) < 2 {
		name, _ := xenapi.Host.GetNameLabel(session, hosts[0])
		panic(fmt.Sprintf("%s has %d spare NIC(s); a bond needs two that aren't the management interface",
			name, len(spares)))
	}
	fmt.Printf("Bonding:      %s\n", strings.Join(devices, ", "))

	// The bond needs a network to sit on.
	network, err := xenapi.Network.Create(session, xenapi.NetworkRecord{
		NameLabel:       "sdk-example-bond",
		NameDescription: "Created by the SDK example",
		Managed:         true, // as in createNetwork: the zero value would be NETWORK_UNMANAGED
	})
	check(err)

	// The Go binding's Create carries the properties map the other bindings default for you.
	bond, err := xenapi.Bond.Create(session, network, spares, "", xenapi.BondModeBalanceSlb,
		map[string]string{})
	check(err)
	master, _ := xenapi.Bond.GetMaster(session, bond)
	masterDev, _ := xenapi.PIF.GetDevice(session, master)
	mode, _ := xenapi.Bond.GetMode(session, bond)
	fmt.Printf("Bond master:  %s\n", masterDev)
	fmt.Printf("Mode:         %s\n", mode)

	check(xenapi.Bond.Destroy(session, bond))
	check(xenapi.Network.Destroy(session, network))
	left, _ := xenapi.Bond.GetAll(session)
	fmt.Printf("Bonds left:   %d\n", len(left))
	fmt.Println("OK: create-bond")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Bonding:      eth2, eth1
Bond master:  bond0
Mode:         balance-slb
Bonds left:   0
OK: create-bond
```

</details>

## PowerShell

Source: [`powershell/Networking/Invoke-CreateBond.ps1`](../../powershell/Networking/Invoke-CreateBond.ps1)

```powershell
function Invoke-CreateBond {
    <#
    .SYNOPSIS
        Create a NIC bond.
    .DESCRIPTION
        Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond
        back, then dissolve it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1

    # Pick up any NIC racked since the host booted. Cheap, and without it a card added a moment ago is
    # not there to bond. PIF.scan takes a HOST, so Invoke-XenPIF cannot bind it - its parameter sets all
    # name a PIF - and the call goes over JSON-RPC instead. Same escape hatch the event API needs.
    Invoke-XenMethod -Session $session -Method 'PIF.scan' -Params @($xenHost.opaque_ref)

    # Spare NICs only. A bond that includes the management interface moves the management address onto
    # the bond master — on a real host that is how you lose the connection you are working over.
    $spares = Get-XenPIF | Where-Object { $_.host -eq $xenHost.opaque_ref -and -not $_.management -and $_.physical } |
        Select-Object -First 2
    if (@($spares).Count -lt 2) {
        throw "$($xenHost.name_label) has $(@($spares).Count) spare NIC(s); a bond needs two that aren't the management interface"
    }
    Write-Host "Bonding:      $(($spares | ForEach-Object { $_.device }) -join ', ')"

    # The bond needs a network to sit on.
    $network = New-XenNetwork -NameLabel 'sdk-example-bond' -NameDescription 'Created by the SDK example' -PassThru

    $bond = New-XenBond -Network $network.opaque_ref -Members $spares.opaque_ref -MAC '' -Mode balance_slb -PassThru
    $master = Get-XenPIF -Ref $bond.master
    Write-Host "Bond master:  $($master.device)"
    Write-Host "Mode:         $($bond.mode)"

    Remove-XenBond -Ref $bond.opaque_ref
    Remove-XenNetwork -Ref $network.opaque_ref
    Write-Host "Bonds left:   $(@(Get-XenBond).Count)"
    Write-Host "OK: create-bond"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Bonding:      eth1, eth2
Bond master:  bond0
Mode:         balance_slb
Bonds left:   0
OK: create-bond
```

</details>

## xe CLI

Source: [`cli/networking/create-bond.sh`](../../cli/networking/create-bond.sh)

```bash
# Create a NIC bond.
#
# Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond back, then
# dissolve it.
#
# Run it:
#   ./workflows.sh create-bond https://xenserver root "$password"

create_bond() {
    # NOT `host`: that is the script-level variable the xe() wrapper passes to -s, and shadowing it
    # replaces the server address with a uuid, after which every call fails with "No hostname was
    # specified" and the cause is nowhere near the symptom.
    local host_uuid spares network bond master
    host_uuid=$(first_csv "$(xe host-list --minimal)")

    # Pick up any NIC racked since the host booted; without it a card added a moment ago is not there
    # to bond.
    xe pif-scan host-uuid=$host_uuid

    # Spare NICs only. A bond that includes the management interface moves the management address onto
    # the bond master - on a real host that is how you lose the connection you are working over.
    spares=$(xe pif-list host-uuid="$host_uuid" management=false physical=true --minimal)
    if [ "$(count_csv "$spares")" -lt 2 ]; then
        echo "$(xe host-param-get uuid=$host_uuid param-name=name-label) has $(count_csv "$spares") spare NIC(s); a bond needs two that aren't the management interface" >&2
        return 1
    fi
    spares="$(first_csv "$spares"),$(nth_csv "$spares" 2)"
    echo "Bonding:      $spares"

    network=$(xe network-create name-label=sdk-example-bond)
    bond=$(xe bond-create network-uuid="$network" pif-uuids="$spares" mode=balance-slb)
    master=$(xe bond-list uuid="$bond" params=master --minimal)
    echo "Bond master:  $(xe pif-list uuid="$master" params=device --minimal)"
    echo "Mode:         $(xe bond-list uuid="$bond" params=mode --minimal)"

    xe bond-destroy uuid="$bond"
    xe network-destroy uuid="$network"
    echo "Bonds left:   $(count_csv "$(xe bond-list --minimal)")"
    echo "OK: create-bond"
}
```

<details><summary>Sample output</summary>

```text
Bonding:      00000001-0000-0000-2600-000000000000,00000001-0000-0000-2800-000000000000
Bond master:  bond0
Mode:         balance-slb
Bonds left:   0
OK: create-bond
```

</details>
