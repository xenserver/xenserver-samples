<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# List networks

Enumerate the pool's networks with their physical and virtual interface counts.

Workflow `list-networks`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Networking/ListNetworks.cs`](../../csharp/Networking/ListNetworks.cs)

```csharp
/// <summary>
/// Enumerate the pool's networks with their physical and virtual interface counts.
/// </summary>
/// <example>
/// <code>
/// Workflows.ListNetworks("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ListNetworks(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var nets = Network.get_all_records(session).Values.OrderBy(n => n.name_label).ToList();
    Console.WriteLine($"Networks ({nets.Count}):");
    foreach (var net in nets)
        Console.WriteLine($"  - {net.name_label}: {net.PIFs.Count} PIF(s), {net.VIFs.Count} VIF(s)");
    Console.WriteLine("OK: list-networks");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Networks (4):
  - Host internal management network: 0 PIF(s), 0 VIF(s)
  - Pool-wide network associated with eth0: 2 PIF(s), 5 VIF(s)
  - Pool-wide network associated with eth1: 2 PIF(s), 0 VIF(s)
  - Pool-wide network associated with eth2: 2 PIF(s), 0 VIF(s)
OK: list-networks
```

</details>

## Python

Source: [`python/networking/list_networks.py`](../../python/networking/list_networks.py)

```python
"""List networks.

Enumerate the pool's networks with their physical and virtual interface counts.

Run it::

    list_networks("https://xenserver", "root", password)
"""

from connection import connect


def list_networks(url, username, password):
    """List the pool's networks with their attached PIF and VIF counts."""
    session = connect(url, username, password)
    nets = sorted(session.xenapi.network.get_all_records().values(), key=lambda n: n["name_label"])
    print("Networks (%d):" % len(nets))
    for net in nets:
        print("  - %s: %d PIF(s), %d VIF(s)"
              % (net["name_label"], len(net["PIFs"]), len(net["VIFs"])))
    print("OK: list-networks")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Networks (4):
  - Host internal management network: 0 PIF(s), 0 VIF(s)
  - Pool-wide network associated with eth0: 2 PIF(s), 4 VIF(s)
  - Pool-wide network associated with eth1: 2 PIF(s), 0 VIF(s)
  - Pool-wide network associated with eth2: 2 PIF(s), 0 VIF(s)
OK: list-networks
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/networking/ListNetworks.java`](../../java/src/main/java/com/xenserver/samples/networking/ListNetworks.java)

```java
package com.xenserver.samples.networking;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class ListNetworks {
    private ListNetworks() {
    }

    /**
     * List networks.
     *
     * <p>Enumerate the pool's networks with their physical and virtual interface counts.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ListNetworks.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        java.util.List<Network.Record> nets = new java.util.ArrayList<>(Network.getAllRecords(conn).values());
        nets.sort(java.util.Comparator.comparing((Network.Record n) -> n.nameLabel));
        System.out.println("Networks (" + nets.size() + "):");
        for (Network.Record net : nets)
            System.out.println("  - " + net.nameLabel + ": " + net.PIFs.size() + " PIF(s), " + net.VIFs.size() + " VIF(s)");
        System.out.println("OK: list-networks");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Networks (4):
  - Host internal management network: 0 PIF(s), 0 VIF(s)
  - Pool-wide network associated with eth0: 2 PIF(s), 5 VIF(s)
  - Pool-wide network associated with eth1: 2 PIF(s), 0 VIF(s)
  - Pool-wide network associated with eth2: 2 PIF(s), 0 VIF(s)
OK: list-networks
```

</details>

## Go

Source: [`go/list_networks.go`](../../go/list_networks.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// listNetworks - List networks.
//
// Enumerate the pool's networks with their physical and virtual interface counts.
//
// Run it:
//
//	listNetworks("https://xenserver", "root", password)
func listNetworks(url, user, password string) {
	session := connect(url, user, password)
	nets, err := xenapi.Network.GetAllRecords(session)
	check(err)
	fmt.Printf("Networks (%d):\n", len(nets))
	for _, net := range nets {
		fmt.Printf("  - %s: %d PIF(s), %d VIF(s)\n", net.NameLabel, len(net.PIFs), len(net.VIFs))
	}
	fmt.Println("OK: list-networks")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Networks (4):
  - Pool-wide network associated with eth0: 2 PIF(s), 5 VIF(s)
  - Pool-wide network associated with eth1: 2 PIF(s), 0 VIF(s)
  - Pool-wide network associated with eth2: 2 PIF(s), 0 VIF(s)
  - Host internal management network: 0 PIF(s), 0 VIF(s)
OK: list-networks
```

</details>

## PowerShell

Source: [`powershell/Networking/Invoke-ListNetworks.ps1`](../../powershell/Networking/Invoke-ListNetworks.ps1)

```powershell
function Invoke-ListNetworks {
    <#
    .SYNOPSIS
        List networks.
    .DESCRIPTION
        Enumerate the pool's networks with their physical and virtual interface counts.
    .EXAMPLE
        Invoke-ListNetworks -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $nets = Get-XenNetwork | Sort-Object name_label
    Write-Host "Networks ($(@($nets).Count)):"
    $nets | ForEach-Object {
        Write-Host "  - $($_.name_label): $(@($_.PIFs).Count) PIF(s), $(@($_.VIFs).Count) VIF(s)"
    }
    Write-Host "OK: list-networks"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Networks (4):
  - Host internal management network: 0 PIF(s), 0 VIF(s)
  - Pool-wide network associated with eth0: 2 PIF(s), 5 VIF(s)
  - Pool-wide network associated with eth1: 2 PIF(s), 0 VIF(s)
  - Pool-wide network associated with eth2: 2 PIF(s), 0 VIF(s)
OK: list-networks
```

</details>

## xe CLI

Source: [`cli/networking/list-networks.sh`](../../cli/networking/list-networks.sh)

```bash
# List networks.
#
# Enumerate the pool's networks with their physical and virtual interface counts.
#
# Run it:
#   ./workflows.sh list-networks https://xenserver root "$password"

list_networks() {
    echo "Networks:"
    xe network-list params=name-label,bridge
    echo "OK: list-networks"
}
```

<details><summary>Example output</summary>

```text
Networks:
name-label ( RW): Pool-wide network associated with eth0
    bridge ( RO): xenbr0

name-label ( RW): Pool-wide network associated with eth1
    bridge ( RO): xenbr1

name-label ( RW): Pool-wide network associated with eth2
    bridge ( RO): xenbr2

name-label ( RW): Host internal management network
    bridge ( RO): xenapi
OK: list-networks
```

</details>
