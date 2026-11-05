<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create a network

Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to each other privately.

Workflow `create-network`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Networking/CreateNetwork.cs`](../../csharp/Networking/CreateNetwork.cs)

```csharp
/// <summary>
/// Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to each
/// other privately.
/// </summary>
/// <example>
/// <code>
/// Workflows.CreateNetwork("https://xenserver", "root", password, "sdk-example-net");
/// </code>
/// </example>
public static void CreateNetwork(string url, string user, string password,
    string networkName = "sdk-example-net")
{
    var session = Connect(url, user, password);
    var record = new Network
    {
        name_label = networkName,
        name_description = "Internal network created by the SDK example",
        MTU = 1500,
        other_config = new Dictionary<string, string>(),
    };
    var netRef = Network.create(session, record);
    Console.WriteLine($"Created network: {Network.get_uuid(session, netRef.opaque_ref)}");

    // Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this is
    // a property of the network rather than of any one interface on it.
    Network.set_MTU(session, netRef.opaque_ref, 9000);
    Console.WriteLine($"MTU now:         {Network.get_MTU(session, netRef.opaque_ref)}");

    Network.destroy(session, netRef.opaque_ref);
    Console.WriteLine("OK: create-network");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Created network: 00000001-0000-0000-c30a-000000000000
MTU now:         9000
OK: create-network
```

</details>

## Python

Source: [`python/networking/create_network.py`](../../python/networking/create_network.py)

```python
"""Create a network.

Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to
each other privately.

Run it::

    create_network("https://xenserver", "root", password, "sdk-example-net")
"""

from connection import connect


def create_network(url, username, password, network_name="sdk-example-net"):
    """Create an internal network (an isolated switch with no physical NIC)."""
    session = connect(url, username, password)
    net_ref = session.xenapi.network.create({
        "name_label": network_name,
        "name_description": "Internal network created by the SDK example",
        "MTU": "1500",
        "other_config": {},
    })
    print("Created network: %s" % session.xenapi.network.get_uuid(net_ref))

    # Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this is
    # a property of the network rather than of any one interface on it.
    session.xenapi.network.set_MTU(net_ref, "9000")
    print("MTU now:         %s" % session.xenapi.network.get_MTU(net_ref))

    session.xenapi.network.destroy(net_ref)
    print("OK: create-network")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Created network: 00000001-0000-0000-6e0a-000000000000
MTU now:         9000
OK: create-network
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/networking/CreateNetwork.java`](../../java/src/main/java/com/xenserver/samples/networking/CreateNetwork.java)

```java
package com.xenserver.samples.networking;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class CreateNetwork {
    private CreateNetwork() {
    }

    /**
     * Create a network.
     *
     * <p>Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to
     * each other privately.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateNetwork.run("https://xenserver", "root", password, "sdk-example-net");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String networkName) throws Exception {
        Connection conn = connect(url, user, password);
        Network.Record record = new Network.Record();
        record.nameLabel = networkName;
        record.nameDescription = "Internal network created by the SDK example";
        record.MTU = 1500L;
        record.otherConfig = new java.util.HashMap<>();
        // Managed by xapi (bridge and PIFs created for it). Say so: this binding sends every field,
        // and an unset boolean goes as false - an unmanaged network, which a bond refuses.
        record.managed = true;

        Network net = Network.create(conn, record);
        System.out.println("Created network: " + net.getUuid(conn));

        // Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this
        // is a property of the network rather than of any one interface on it.
        net.setMTU(conn, 9000L);
        System.out.println("MTU now:         " + net.getMTU(conn));

        net.destroy(conn);
        System.out.println("OK: create-network");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
Created network: 00000001-0000-0000-150b-000000000000
MTU now:         9000
OK: create-network
```

</details>

## Go

Source: [`go/create_network.go`](../../go/create_network.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// createNetwork - Create a network.
//
// Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to
// each other privately.
//
// Run it:
//
//	createNetwork("https://xenserver", "root", password, "sdk-example-net")
func createNetwork(url, user, password, networkName string) {
	session := connect(url, user, password)
	netRef, err := xenapi.Network.Create(session, xenapi.NetworkRecord{
		NameLabel:       networkName,
		NameDescription: "Internal network created by the SDK example",
		MTU:             1500,
		OtherConfig:     map[string]string{},
		// Managed by xapi (bridge and PIFs created for it). Say so: the binding sends every field, and
		// the zero value is false - an unmanaged network, which a bond refuses.
		Managed: true,
	})
	check(err)
	uuid, _ := xenapi.Network.GetUUID(session, netRef)
	fmt.Printf("Created network: %s\n", uuid)

	// Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this is a
	// property of the network rather than of any one interface on it.
	check(xenapi.Network.SetMTU(session, netRef, 9000))
	mtu, _ := xenapi.Network.GetMTU(session, netRef)
	fmt.Printf("MTU now:         %d\n", mtu)

	check(xenapi.Network.Destroy(session, netRef))
	fmt.Println("OK: create-network")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Created network: 00000001-0000-0000-cb0a-000000000000
MTU now:         9000
OK: create-network
```

</details>

## PowerShell

Source: [`powershell/Networking/Invoke-CreateNetwork.ps1`](../../powershell/Networking/Invoke-CreateNetwork.ps1)

```powershell
function Invoke-CreateNetwork {
    <#
    .SYNOPSIS
        Create a network.
    .DESCRIPTION
        Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to
        each other privately.
    .EXAMPLE
        Invoke-CreateNetwork -Url https://xenserver -UserName root -Password $password -NetworkName 'sdk-example-net'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$NetworkName = "sdk-example-net"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $net = New-XenNetwork -NameLabel $NetworkName `
        -NameDescription "Internal network created by the SDK example" -MTU 1500 -PassThru
    Write-Host "Created network: $($net.uuid)"

    # Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this is a
    # property of the network rather than of any one interface on it.
    $net | Set-XenNetwork -MTU 9000
    Write-Host "MTU now:         $((Get-XenNetwork -Ref $net.opaque_ref).MTU)"

    $net | Remove-XenNetwork
    Write-Host "OK: create-network"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Created network: 00000001-0000-0000-1a0b-000000000000
MTU now:         9000
OK: create-network
```

</details>

## xe CLI

Source: [`cli/networking/create-network.sh`](../../cli/networking/create-network.sh)

```bash
# Create a network.
#
# Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to each other
# privately.
#
# Run it:
#   ./workflows.sh create-network https://xenserver root "$password"

create_network() {
    net=$(xe network-create name-label=xe-example-net)
    echo "Created network: $net"

    # Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this
    # is a property of the network rather than of any one interface on it.
    xe network-param-set uuid=$net MTU=9000
    echo "MTU now:         $(xe network-param-get uuid=$net param-name=MTU)"
    xe network-destroy uuid=$net
    echo "OK: create-network"
}
```

<details><summary>Sample output</summary>

```text
Created network: 00000001-0000-0000-6f0a-000000000000
MTU now:         9000
OK: create-network
```

</details>
