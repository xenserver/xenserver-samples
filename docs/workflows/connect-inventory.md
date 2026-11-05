<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Connect & inventory

Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual machines with their power state. This is the starting point for every session.

Workflow `connect-inventory`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/GettingStarted/ConnectInventory.cs`](../../csharp/GettingStarted/ConnectInventory.cs)

```csharp
/// <summary>
/// Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual
/// machines with their power state. This is the starting point for every session.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConnectInventory("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ConnectInventory(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all_records(session).Values.First();
    Console.WriteLine($"Connected to pool: {pool.name_label}");

    var hosts = Host.get_all_records(session);
    Console.WriteLine($"Hosts ({hosts.Count}):");
    foreach (var host in hosts.Values)
        Console.WriteLine($"  - {host.name_label} ({host.address})");

    var vms = VM.get_all_records(session).Values
        .Where(v => !v.is_a_template && !v.is_control_domain).ToList();
    Console.WriteLine($"VMs ({vms.Count}):");
    foreach (var vm in vms)
        Console.WriteLine($"  - {vm.name_label} [{vm.power_state}]");

    Console.WriteLine("OK: connect-inventory");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Connected to pool: sdk-pool
Hosts (2):
  - sdk-host1 (127.0.0.1)
  - sdk-host2 (198.51.100.12)
VMs (4):
  - web-01 [Running]
  - db-01 [Halted]
  - cache-01 [Running]
  - secure-01 [Halted]
OK: connect-inventory
```

</details>

## Python

Source: [`python/getting_started/connect_inventory.py`](../../python/getting_started/connect_inventory.py)

```python
"""Connect & inventory.

Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual
machines with their power state. This is the starting point for every session.

Run it::

    connect_inventory("https://xenserver", "root", password)
"""

from connection import connect


def connect_inventory(url, username, password):
    """Log in and take an inventory of the pool: its name, its hosts and its VMs."""
    session = connect(url, username, password)
    pool = list(session.xenapi.pool.get_all_records().values())[0]
    print("Connected to pool: %s" % pool["name_label"])

    hosts = session.xenapi.host.get_all_records()
    print("Hosts (%d):" % len(hosts))
    for host in hosts.values():
        print("  - %s (%s)" % (host["name_label"], host["address"]))

    vms = [v for v in session.xenapi.VM.get_all_records().values()
           if not v["is_a_template"] and not v["is_control_domain"]]
    print("VMs (%d):" % len(vms))
    for vm in vms:
        print("  - %s [%s]" % (vm["name_label"], vm["power_state"]))

    print("OK: connect-inventory")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Connected to pool: sdk-pool
Hosts (2):
  - sdk-host1 (127.0.0.1)
  - sdk-host2 (198.51.100.12)
VMs (4):
  - web-01 [Running]
  - db-01 [Halted]
  - cache-01 [Running]
  - secure-01 [Halted]
OK: connect-inventory
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/gettingstarted/ConnectInventory.java`](../../java/src/main/java/com/xenserver/samples/gettingstarted/ConnectInventory.java)

```java
package com.xenserver.samples.gettingstarted;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConnectInventory {
    private ConnectInventory() {
    }

    /**
     * Connect &amp; inventory.
     *
     * <p>Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the
     * virtual machines with their power state. This is the starting point for every session.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConnectInventory.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Pool.Record pool = Pool.getAllRecords(conn).values().iterator().next();
        System.out.println("Connected to pool: " + pool.nameLabel);

        Map<Host, Host.Record> hosts = Host.getAllRecords(conn);
        System.out.println("Hosts (" + hosts.size() + "):");
        for (Host.Record h : hosts.values())
            System.out.println("  - " + h.nameLabel + " (" + h.address + ")");

        int count = 0;
        System.out.println("VMs:");
        for (VM.Record v : VM.getAllRecords(conn).values()) {
            if (!v.isATemplate && !v.isControlDomain) {
                count++;
                System.out.println("  - " + v.nameLabel + " [" + v.powerState + "]");
            }
        }
        System.out.println("VMs (" + count + ")");

        System.out.println("OK: connect-inventory");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Connected to pool: sdk-pool
Hosts (2):
  - sdk-host1 (127.0.0.1)
  - sdk-host2 (198.51.100.12)
VMs:
  - web-01 [Running]
  - db-01 [Halted]
  - cache-01 [Running]
  - secure-01 [Halted]
VMs (4)
OK: connect-inventory
```

</details>

## Go

Source: [`go/connect_inventory.go`](../../go/connect_inventory.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// connectInventory - Connect & inventory.
//
// Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the
// virtual machines with their power state. This is the starting point for every session.
//
// Run it:
//
//	connectInventory("https://xenserver", "root", password)
func connectInventory(url, user, password string) {
	session := connect(url, user, password)
	pools, err := xenapi.Pool.GetAllRecords(session)
	check(err)
	for _, pool := range pools {
		fmt.Printf("Connected to pool: %s\n", pool.NameLabel)
		break
	}

	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	fmt.Printf("Hosts (%d):\n", len(hosts))
	for _, host := range hosts {
		fmt.Printf("  - %s (%s)\n", host.NameLabel, host.Address)
	}

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	count := 0
	for _, vm := range vms {
		if !vm.IsATemplate && !vm.IsControlDomain {
			count++
			fmt.Printf("  - %s [%s]\n", vm.NameLabel, vm.PowerState)
		}
	}
	fmt.Printf("VMs (%d)\n", count)

	fmt.Println("OK: connect-inventory")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Connected to pool: sdk-pool
Hosts (2):
  - sdk-host2 (198.51.100.12)
  - sdk-host1 (127.0.0.1)
  - web-01 [Running]
  - secure-01 [Halted]
  - db-01 [Halted]
  - cache-01 [Running]
VMs (4)
OK: connect-inventory
```

</details>

## PowerShell

Source: [`powershell/GettingStarted/Invoke-ConnectInventory.ps1`](../../powershell/GettingStarted/Invoke-ConnectInventory.ps1)

```powershell
function Invoke-ConnectInventory {
    <#
    .SYNOPSIS
        Connect & inventory.
    .DESCRIPTION
        Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual
        machines with their power state. This is the starting point for every session.
    .EXAMPLE
        Invoke-ConnectInventory -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    Write-Host "Connected to pool: $($pool.name_label)"

    $hosts = Get-XenHost
    Write-Host "Hosts ($($hosts.Count)):"
    Get-XenHost | ForEach-Object { Write-Host "  - $($_.name_label) ($($_.address))" }

    $vms = Get-XenVM | Where-Object { -not $_.is_a_template -and -not $_.is_control_domain }
    Write-Host "VMs ($($vms.Count)):"
    $vms | ForEach-Object { Write-Host "  - $($_.name_label) [$($_.power_state)]" }

    Write-Host "OK: connect-inventory"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Connected to pool: sdk-pool
Hosts (2):
  - sdk-host1 (127.0.0.1)
  - sdk-host2 (198.51.100.12)
VMs (4):
  - web-01 [Running]
  - db-01 [Halted]
  - cache-01 [Running]
  - secure-01 [Halted]
OK: connect-inventory
```

</details>

## xe CLI

Source: [`cli/getting-started/connect-inventory.sh`](../../cli/getting-started/connect-inventory.sh)

```bash
# Connect & inventory.
#
# Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual machines
# with their power state. This is the starting point for every session.
#
# Run it:
#   ./workflows.sh connect-inventory https://xenserver root "$password"

connect_inventory() {
    echo "Connected to pool: $(xe pool-list params=name-label --minimal)"
    echo "Hosts: $(xe host-list params=name-label --minimal)"
    echo "VMs:"
    xe vm-list is-control-domain=false params=name-label,power-state
    echo "OK: connect-inventory"
}
```

<details><summary>Example output</summary>

```text
Connected to pool: sdk-pool
Hosts: sdk-host1,sdk-host2
VMs:
name-label ( RW) : web-01
power-state ( RO): running

name-label ( RW) : db-01
power-state ( RO): halted

name-label ( RW) : cache-01
power-state ( RO): running

name-label ( RW) : secure-01
power-state ( RO): halted
OK: connect-inventory
```

</details>
