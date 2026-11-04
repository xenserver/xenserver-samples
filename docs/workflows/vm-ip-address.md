<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Get a VM's IP address

Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.

Workflow `vm-ip-address`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/VirtualMachines/VmIpAddress.cs`](../../csharp/VirtualMachines/VmIpAddress.cs)

```csharp
/// <summary> Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
/// </summary> <example> <code> Workflows.VmIpAddress("https://xenserver", "root", password); </code>
/// </example> <remarks> A VM that has only just started may not have reported in yet (no guest_metrics at
/// all, or an empty networks map) - retry for a while rather than giving up on the first look. </remarks>
public static void VmIpAddress(string url, string user, string password,
    int timeoutSeconds = 60, int intervalSeconds = 2)
{
    var session = Connect(url, user, password);
    var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
    while (true)
    {
        // A running guest reports its IP in networks, keyed "<vif device>/ip" (e.g. "0/ip").
        var vm = VM.get_all_records(session).Values.FirstOrDefault(v =>
            v.power_state == vm_power_state.Running && !v.is_a_template && !v.is_control_domain
            && v.guest_metrics.opaque_ref != "OpaqueRef:NULL");
        string ip = null;
        if (vm != null)
        {
            var networks = VM_guest_metrics.get_record(session, vm.guest_metrics).networks;
            networks.TryGetValue("0/ip", out ip);
        }
        if (!string.IsNullOrEmpty(ip))
        {
            Console.WriteLine($"  {vm.name_label}: {ip}");
            break;
        }
        if (DateTime.UtcNow > deadline)
            throw new Exception($"no running guest reported an IP address within {timeoutSeconds}s");
        System.Threading.Thread.Sleep(intervalSeconds * 1000);
    }
    Console.WriteLine("OK: vm-ip-address");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
  web-01: 198.51.100.51
OK: vm-ip-address
```

</details>

## Python

Source: [`python/virtual_machines/vm_ip_address.py`](../../python/virtual_machines/vm_ip_address.py)

```python
"""Get a VM's IP address.

Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
"""

import time

from connection import connect


def vm_ip_address(url, username, password, timeout=60, interval=2):
    """Read a running VM's IP from its guest metrics (VM_guest_metrics.networks).

    A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
    empty networks map) - retry for a while rather than giving up on the first look."""
    session = connect(url, username, password)
    deadline = time.time() + timeout
    while True:
        # A running guest reports its IP in networks, keyed "<vif device>/ip" (e.g. "0/ip").
        vm = next((v for v in session.xenapi.VM.get_all_records().values()
                   if v["power_state"] == "Running" and not v["is_a_template"]
                   and not v["is_control_domain"] and v["guest_metrics"] != "OpaqueRef:NULL"), None)
        ip = None
        if vm is not None:
            networks = session.xenapi.VM_guest_metrics.get_record(vm["guest_metrics"])["networks"]
            ip = networks.get("0/ip")
        if ip:
            print("  %s: %s" % (vm["name_label"], ip))
            break
        if time.time() > deadline:
            raise RuntimeError("no running guest reported an IP address within %ds" % timeout)
        time.sleep(interval)
    print("OK: vm-ip-address")
    session.logout()
```

<details><summary>Sample output</summary>

```text
  web-01: 198.51.100.51
OK: vm-ip-address
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/VmIpAddress.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/VmIpAddress.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class VmIpAddress {
    private VmIpAddress() {
    }

    /**
     * Get a VM's IP address.
     *
     * <p>Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
     *
     * <p>A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
     * empty networks map) - retry for a while rather than giving up on the first look.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * VmIpAddress.run("https://xenserver", "root", password, 60_000, 2_000);
     * }</pre>
     */
    public static void run(String url, String user, String password,
            long timeoutMs, long intervalMs) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            long deadline = System.currentTimeMillis() + timeoutMs;
            while (true) {
                // A running guest reports its IP in networks, keyed "<vif device>/ip" (e.g. "0/ip").
                VM.Record vm = null;
                for (VM.Record r : VM.getAllRecords(conn).values())
                    if (r.powerState == Types.VmPowerState.RUNNING && !r.isATemplate && !r.isControlDomain
                            && !r.guestMetrics.toWireString().equals("OpaqueRef:NULL")) { vm = r; break; }
                String ip = null;
                if (vm != null) {
                    Map<String, String> networks = vm.guestMetrics.getRecord(conn).networks;
                    ip = networks.get("0/ip");
                }
                if (ip != null) {
                    System.out.println("  " + vm.nameLabel + ": " + ip);
                    break;
                }
                if (System.currentTimeMillis() > deadline)
                    throw new RuntimeException("no running guest reported an IP address within "
                            + (timeoutMs / 1000) + "s");
                Thread.sleep(intervalMs);
            }
            System.out.println("OK: vm-ip-address");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Sample output</summary>

```text
  web-01: 198.51.100.51
OK: vm-ip-address
```

</details>

## Go

Source: [`go/vm_ip_address.go`](../../go/vm_ip_address.go)

```go
package main

import (
	"fmt"
	"strconv"
	"time"

	"go/xenapi"
)

// vmIpAddress - Get a VM's IP address.
//
// Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
//
// A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
// empty networks map) - retry for a while rather than giving up on the first look. The CLI version
// of this example already does this; timeoutStr and intervalStr bring the SDK languages in line
// with it (seconds, as decimal strings).
func vmIpAddress(url, user, password, timeoutStr, intervalStr string) {
	timeout, err := strconv.Atoi(timeoutStr)
	check(err)
	interval, err := strconv.Atoi(intervalStr)
	check(err)
	session := connect(url, user, password)

	deadline := time.Now().Add(time.Duration(timeout) * time.Second)
	for {
		// A running guest reports its IP in VM_guest_metrics.networks, keyed "<vif device>/ip".
		vms, err := xenapi.VM.GetAllRecords(session)
		check(err)
		var vm xenapi.VMRecord
		found := false
		for _, r := range vms {
			if r.PowerState == xenapi.VMPowerStateRunning && !r.IsATemplate && !r.IsControlDomain &&
				r.GuestMetrics != xenapi.VMGuestMetricsRef("OpaqueRef:NULL") {
				vm, found = r, true
				break
			}
		}
		var ip string
		if found {
			gm, err := xenapi.VMGuestMetrics.GetRecord(session, vm.GuestMetrics)
			check(err)
			ip = gm.Networks["0/ip"]
		}
		if ip != "" {
			fmt.Printf("  %s: %s\n", vm.NameLabel, ip)
			break
		}
		if time.Now().After(deadline) {
			panic(fmt.Sprintf("no running guest reported an IP address within %ds", timeout))
		}
		time.Sleep(time.Duration(interval) * time.Second)
	}
	fmt.Println("OK: vm-ip-address")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
  cache-01: 198.51.100.52
OK: vm-ip-address
```

</details>

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-VmIpAddress.ps1`](../../powershell/VirtualMachines/Invoke-VmIpAddress.ps1)

```powershell
function Invoke-VmIpAddress {
    <#
    .SYNOPSIS
        Get a VM's IP address.
    .DESCRIPTION
        Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
    .EXAMPLE
        Invoke-VmIpAddress -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [int]$TimeoutSeconds = 60,
        [int]$IntervalSeconds = 2
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # A VM that has only just started may not have reported in yet (no guest_metrics at all, or an empty
    # networks map) - retry for a while rather than giving up on the first look.
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        # A running guest reports its IP in networks, keyed "<vif device>/ip" (e.g. "0/ip").
        $vm = Get-XenVM | Where-Object {
            $_.power_state -eq 'Running' -and -not $_.is_a_template -and -not $_.is_control_domain -and
            $_.guest_metrics.opaque_ref -ne 'OpaqueRef:NULL'
        } | Select-Object -First 1
        $ip = $null
        if ($vm) {
            $networks = (Get-XenVMGuestMetrics -Ref $vm.guest_metrics.opaque_ref).networks
            if ($networks.ContainsKey("0/ip")) { $ip = $networks["0/ip"] }
        }
        if ($ip) {
            Write-Host "  $($vm.name_label): $ip"
            break
        }
        if ((Get-Date) -gt $deadline) {
            throw "no running guest reported an IP address within ${TimeoutSeconds}s"
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
    Write-Host "OK: vm-ip-address"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
  web-01: 198.51.100.51
OK: vm-ip-address
```

</details>

## xe CLI

Source: [`cli/virtual-machines/vm-ip-address.sh`](../../cli/virtual-machines/vm-ip-address.sh)

```bash
# Get a VM's IP address.
#
# Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
#
# Run it:
#   ./workflows.sh vm-ip-address https://xenserver root "$password"

vm_ip_address() {
    # A running guest's tools report its IPs in the VM's networks parameter, keyed "<vif device>/ip". Pick
    # one that reports an address (freshly-created VMs and guests without tools report none).
    running=$(xe vm-list power-state=running is-control-domain=false --minimal)
    vm=""; ip=""
    for u in $(each_csv "$running"); do
        ip=$(xe vm-param-get uuid=$u param-name=networks param-key=0/ip 2>/dev/null) || continue
        vm=$u; break
    done
    [ -n "$vm" ] || { vm=$(first_csv "$running"); ip="(no address reported)"; }
    echo "  $(xe vm-param-get uuid=$vm param-name=name-label): $ip"
    echo "OK: vm-ip-address"
}
```

<details><summary>Sample output</summary>

```text
  web-01: 198.51.100.51
OK: vm-ip-address
```

</details>
