<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Get a VM's IP address

Read a VM's IP address (name it with vm_name) from its guest metrics, as reported by the in-guest agent, waiting a while for the agent to report one.

Workflow `vm-ip-address`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-VmIpAddress.ps1`](../../powershell/VirtualMachines/Invoke-VmIpAddress.ps1)

```powershell
function Invoke-VmIpAddress {
    <#
    .SYNOPSIS
        Get a VM's IP address.
    .DESCRIPTION
        Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.
    .EXAMPLE
        Invoke-VmIpAddress -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = 'web-01',
        [int]$TimeoutSeconds = 60,
        [int]$IntervalSeconds = 2
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    # A VM that has only just started may not have reported in yet (no guest_metrics at all, or an empty
    # networks map) - retry for a while before concluding it has no guest agent reporting.
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $ip = $null
    while ($true) {
        # An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
        $current = Get-XenVM -Ref $vm.opaque_ref
        $ip = $null
        if ($current.power_state -eq 'Running' -and $current.guest_metrics -ne 'OpaqueRef:NULL') {
            $networks = (Get-XenVMGuestMetrics -Ref $current.guest_metrics).networks
            if ($networks.ContainsKey("0/ip") -and $networks["0/ip"]) {
                $ip = $networks["0/ip"]
            }
        }
        if ($ip -or (Get-Date) -gt $deadline) { break }
        Start-Sleep -Seconds $IntervalSeconds
    }
    if ($ip) {
        Write-Host "  $($VmName): $ip"
    } else {
        Write-Host "  $($VmName): no IP address reported yet (no guest agent running?)"
    }
    Write-Host "OK: vm-ip-address"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

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
# Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.
#
# Run it:
#   ./workflows.sh vm-ip-address https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (web-01), timeout (60), interval (2)

vm_ip_address() {
    # A VM that has only just started may not have reported in yet (freshly-created VMs and guests
    # without tools report no address) - retry for a while before concluding it has no guest agent
    # reporting.
    local vm_name timeout interval deadline vm power ip
    vm_name=$(param vm_name web-01)
    timeout=$(param timeout 60)
    interval=$(param interval 2)
    vm=$(vm_uuid "$vm_name")
    deadline=$((SECONDS + timeout))
    while true; do
        # An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
        power=$(xe vm-param-get uuid=$vm param-name=power-state)
        ip=""
        if [ "$power" = running ]; then
            ip=$(xe_try vm-param-get uuid=$vm param-name=networks param-key=0/ip 2>/dev/null) || ip=""
        fi
        [ -n "$ip" ] && break
        [ $SECONDS -gt $deadline ] && break
        sleep "$interval"
    done
    if [ -n "$ip" ]; then
        echo "  $vm_name: $ip"
    else
        echo "  $vm_name: no IP address reported yet (no guest agent running?)"
    fi
    ok vm-ip-address
}
```

<details><summary>Example output</summary>

```text
  web-01: 198.51.100.51
OK: vm-ip-address
```

</details>

## Python

Source: [`python/virtual_machines/vm_ip_address.py`](../../python/virtual_machines/vm_ip_address.py)

```python
"""Get a VM's IP address.

Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.

Run it::

    vm_ip_address("https://xenserver", "root", password, "web-01")
"""

import time

from connection import connect
from helpers import is_set, vm_by_name


def vm_ip_address(url, username, password, vm_name="web-01", timeout=60, interval=2):
    """Read the named VM's IP from its guest metrics (VM_guest_metrics.networks).

    A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
    empty networks map) - retry for a while before concluding it has no guest agent reporting."""
    session = connect(url, username, password)
    vm_ref = vm_by_name(session, vm_name)
    deadline = time.time() + timeout
    ip = None
    while True:
        # An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
        record = session.xenapi.VM.get_record(vm_ref)
        if record["power_state"] == "Running" and is_set(record["guest_metrics"]):
            ip = session.xenapi.VM_guest_metrics.get_record(record["guest_metrics"])["networks"].get("0/ip")
            if ip:
                break
        if time.time() > deadline:
            break
        time.sleep(interval)
    if ip:
        print("  %s: %s" % (vm_name, ip))
    else:
        print("  %s: no IP address reported yet (no guest agent running?)" % vm_name)
    print("OK: vm-ip-address")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
  web-01: 198.51.100.51
OK: vm-ip-address
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/VmIpAddress.cs`](../../csharp/VirtualMachines/VmIpAddress.cs)

```csharp
/// <summary>
/// Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.
/// </summary>
/// <example>
/// <code>
/// Workflows.VmIpAddress("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
/// <remarks>
/// A VM that has only just started may not have reported in yet (no guest_metrics at all, or an empty
/// networks map) - retry for a while before concluding it has no guest agent reporting.
/// </remarks>
public static void VmIpAddress(string url, string user, string password, string vmName = "web-01",
    int timeoutSeconds = 60, int intervalSeconds = 2)
{
    var session = Connect(url, user, password);
    var vm = VmByName(session, vmName);
    var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
    string ip = null;
    while (true)
    {
        // An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
        var record = VM.get_record(session, vm);
        if (record.power_state == vm_power_state.Running && !Helper.IsNullOrEmptyOpaqueRef(record.guest_metrics)
            && VM_guest_metrics.get_record(session, record.guest_metrics).networks.TryGetValue("0/ip", out ip)
            && !string.IsNullOrEmpty(ip))
            break;
        ip = null;
        if (DateTime.UtcNow > deadline)
            break;
        System.Threading.Thread.Sleep(intervalSeconds * 1000);
    }
    Console.WriteLine(ip != null
        ? $"  {vmName}: {ip}"
        : $"  {vmName}: no IP address reported yet (no guest agent running?)");
    Console.WriteLine("OK: vm-ip-address");
    session.logout();
}
```

<details><summary>Example output</summary>

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
// Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.
//
// A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
// empty networks map) - retry for a while before concluding it has no guest agent reporting.
// timeoutStr and intervalStr take seconds, as decimal strings (Go's dispatcher passes key=value
// arguments as strings).
func vmIpAddress(url, user, password, vmName, timeoutStr, intervalStr string) {
	timeout, err := strconv.Atoi(timeoutStr)
	check(err)
	interval, err := strconv.Atoi(intervalStr)
	check(err)
	session := connect(url, user, password)
	vm := vmByName(session, vmName)

	deadline := time.Now().Add(time.Duration(timeout) * time.Second)
	var ip string
	for {
		// An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
		record, err := xenapi.VM.GetRecord(session, vm)
		check(err)
		ip = ""
		if record.PowerState == xenapi.VMPowerStateRunning && isSet(record.GuestMetrics) {
			gm, err := xenapi.VMGuestMetrics.GetRecord(session, record.GuestMetrics)
			check(err)
			ip = gm.Networks["0/ip"]
		}
		if ip != "" || time.Now().After(deadline) {
			break
		}
		time.Sleep(time.Duration(interval) * time.Second)
	}
	if ip != "" {
		fmt.Printf("  %s: %s\n", vmName, ip)
	} else {
		fmt.Printf("  %s: no IP address reported yet (no guest agent running?)\n", vmName)
	}
	fmt.Println("OK: vm-ip-address")
	session.Logout()
}
```

<details><summary>Example output</summary>

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

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class VmIpAddress {
    private VmIpAddress() {
    }

    /**
     * Get a VM's IP address.
     *
     * <p>Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.
     *
     * <p>A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
     * empty networks map) - retry for a while before concluding it has no guest agent reporting.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * VmIpAddress.run("https://xenserver", "root", password, "web-01", 60_000, 2_000);
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName,
            long timeoutMs, long intervalMs) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = vmByName(conn, vmName);
            long deadline = System.currentTimeMillis() + timeoutMs;
            String ip = null;
            while (true) {
                // An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
                VM.Record record = vm.getRecord(conn);
                ip = null;
                if (record.powerState == Types.VmPowerState.RUNNING && !record.guestMetrics.isNull()) {
                    Map<String, String> networks = record.guestMetrics.getRecord(conn).networks;
                    ip = networks.get("0/ip");
                }
                if ((ip != null && !ip.isEmpty()) || System.currentTimeMillis() > deadline) break;
                Thread.sleep(intervalMs);
            }
            if (ip != null && !ip.isEmpty()) {
                System.out.println("  " + vmName + ": " + ip);
            } else {
                System.out.println("  " + vmName + ": no IP address reported yet (no guest agent running?)");
            }
            System.out.println("OK: vm-ip-address");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
  web-01: 198.51.100.51
OK: vm-ip-address
```

</details>
