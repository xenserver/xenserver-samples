<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Host information

Read a host's software version, edition and CPU topology (sockets and cores).

Workflow `host-info`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/HostInfo.cs`](../../csharp/HostsAndPools/HostInfo.cs)

```csharp
/// <summary>
/// Read a host's software version, edition and CPU topology (sockets and cores).
/// </summary>
/// <example>
/// <code>
/// Workflows.HostInfo("https://xenserver", "root", password);
/// </code>
/// </example>
public static void HostInfo(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var (hostRef, host) = Host.get_all_records(session).First();
    var sw = host.software_version;
    var cpu = host.cpu_info;
    Console.WriteLine($"Host:     {host.name_label}");
    Console.WriteLine($"Version:  {(sw.TryGetValue("product_version", out var pv) ? pv : "?")}");
    Console.WriteLine($"Edition:  {host.edition}");
    Console.WriteLine($"CPUs:     {(cpu.TryGetValue("cpu_count", out var cc) ? cc : "?")} across " +
                      $"{(cpu.TryGetValue("socket_count", out var sc) ? sc : "?")} socket(s)");
    // The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what
    // you quote to the hardware vendor, so it is the one field here that identifies this machine
    // and not just its model.
    var bios = host.bios_strings;
    string Bios(string k) => bios.TryGetValue(k, out var v) ? v : "?";
    Console.WriteLine($"Hardware: {Bios("system-manufacturer")} {Bios("system-product-name")}");
    Console.WriteLine($"Serial:   {Bios("system-serial-number")}");
    Console.WriteLine($"BIOS:     {Bios("bios-version")}");
    Console.WriteLine("OK: host-info");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Host:     sdk-host1
Version:  9.0.0
Edition:  cloud
CPUs:     8 across 1 socket(s)
Hardware: Dell Inc. PowerEdge R750
Serial:   XPSIM017RT
BIOS:     2.15.1
OK: host-info
```

</details>

## Python

Source: [`python/hosts_and_pools/host_info.py`](../../python/hosts_and_pools/host_info.py)

```python
"""Host information.

Read a host's software version, edition and CPU topology (sockets and cores).

Run it::

    host_info("https://xenserver", "root", password)
"""

from connection import connect


def host_info(url, username, password):
    """Read a host's identity: product version, edition and CPU topology."""
    session = connect(url, username, password)
    host = next(iter(session.xenapi.host.get_all_records().values()))
    sw = host["software_version"]
    cpu = host["cpu_info"]
    print("Host:     %s" % host["name_label"])
    print("Version:  %s" % sw.get("product_version", "?"))
    print("Edition:  %s" % host["edition"])
    print("CPUs:     %s across %s socket(s)"
          % (cpu.get("cpu_count", "?"), cpu.get("socket_count", "?")))

    # The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what you
    # quote to the hardware vendor, so it is the one field here that identifies this machine and not
    # just its model.
    bios = host["bios_strings"]
    print("Hardware: %s %s" % (bios.get("system-manufacturer", "?"),
                               bios.get("system-product-name", "?")))
    print("Serial:   %s" % bios.get("system-serial-number", "?"))
    print("BIOS:     %s" % bios.get("bios-version", "?"))
    print("OK: host-info")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Host:     sdk-host1
Version:  9.0.0
Edition:  cloud
CPUs:     8 across 1 socket(s)
Hardware: Dell Inc. PowerEdge R750
Serial:   XPSIM017RT
BIOS:     2.15.1
OK: host-info
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/HostInfo.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/HostInfo.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class HostInfo {
    private HostInfo() {
    }

    /**
     * Host information.
     *
     * <p>Read a host's software version, edition and CPU topology (sockets and cores).
     *
     * <p>Run it:
     *
     * <pre>{@code
     * HostInfo.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Host.Record host = Host.getAllRecords(conn).values().iterator().next();
        Map<String, String> sw = host.softwareVersion;
        Map<String, String> cpu = host.cpuInfo;
        System.out.println("Host:     " + host.nameLabel);
        System.out.println("Version:  " + (sw.containsKey("product_version") ? sw.get("product_version") : "?"));
        System.out.println("Edition:  " + host.edition);
        System.out.println("CPUs:     " + (cpu.containsKey("cpu_count") ? cpu.get("cpu_count") : "?")
                + " across " + (cpu.containsKey("socket_count") ? cpu.get("socket_count") : "?") + " socket(s)");
        // The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what
        // you quote to the hardware vendor, so it identifies this machine and not just its model.
        Map<String, String> bios = host.biosStrings;
        System.out.println("Hardware: " + bios.getOrDefault("system-manufacturer", "?")
                + " " + bios.getOrDefault("system-product-name", "?"));
        System.out.println("Serial:   " + bios.getOrDefault("system-serial-number", "?"));
        System.out.println("BIOS:     " + bios.getOrDefault("bios-version", "?"));
        System.out.println("OK: host-info");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
Host:     sdk-host1
Version:  9.0.0
Edition:  cloud
CPUs:     8 across 1 socket(s)
Hardware: Dell Inc. PowerEdge R750
Serial:   XPSIM017RT
BIOS:     2.15.1
OK: host-info
```

</details>

## Go

Source: [`go/host_info.go`](../../go/host_info.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// hostInfo - Host information.
//
// Read a host's software version, edition and CPU topology (sockets and cores).
//
// Run it:
//
//	hostInfo("https://xenserver", "root", password)
func hostInfo(url, user, password string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var host xenapi.HostRecord
	for _, h := range hosts {
		host = h
		break
	}

	// A map lookup that falls back to "?" for a key the host does not report.
	get := func(m map[string]string, key string) string {
		if v, ok := m[key]; ok {
			return v
		}
		return "?"
	}

	fmt.Printf("Host:     %s\n", host.NameLabel)
	fmt.Printf("Version:  %s\n", get(host.SoftwareVersion, "product_version"))
	fmt.Printf("Edition:  %s\n", host.Edition)
	fmt.Printf("CPUs:     %s across %s socket(s)\n",
		get(host.CPUInfo, "cpu_count"), get(host.CPUInfo, "socket_count"))
	// The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what you
	// quote to the hardware vendor, so it is the one field here that identifies this machine, not its model.
	fmt.Printf("Hardware: %s %s\n", get(host.BiosStrings, "system-manufacturer"),
		get(host.BiosStrings, "system-product-name"))
	fmt.Printf("Serial:   %s\n", get(host.BiosStrings, "system-serial-number"))
	fmt.Printf("BIOS:     %s\n", get(host.BiosStrings, "bios-version"))
	fmt.Println("OK: host-info")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Host:     sdk-host1
Version:  9.0.0
Edition:  cloud
CPUs:     8 across 1 socket(s)
Hardware: Dell Inc. PowerEdge R750
Serial:   XPSIM017RT
BIOS:     2.15.1
OK: host-info
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-HostInfo.ps1`](../../powershell/HostsAndPools/Invoke-HostInfo.ps1)

```powershell
function Invoke-HostInfo {
    <#
    .SYNOPSIS
        Host information.
    .DESCRIPTION
        Read a host's software version, edition and CPU topology (sockets and cores).
    .EXAMPLE
        Invoke-HostInfo -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $sw = $xenHost.software_version
    $cpu = $xenHost.cpu_info
    $pv = if ($sw.ContainsKey("product_version")) { $sw["product_version"] } else { "?" }
    $cc = if ($cpu.ContainsKey("cpu_count")) { $cpu["cpu_count"] } else { "?" }
    $sc = if ($cpu.ContainsKey("socket_count")) { $cpu["socket_count"] } else { "?" }
    Write-Host "Host:     $($xenHost.name_label)"
    Write-Host "Version:  $pv"
    Write-Host "Edition:  $($xenHost.edition)"
    Write-Host "CPUs:     $cc across $sc socket(s)"
    # The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what you
    # quote to the hardware vendor, so it identifies this machine and not just its model.
    $bios = $xenHost.bios_strings
    Write-Host "Hardware: $($bios['system-manufacturer']) $($bios['system-product-name'])"
    Write-Host "Serial:   $($bios['system-serial-number'])"
    Write-Host "BIOS:     $($bios['bios-version'])"
    Write-Host "OK: host-info"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Host:     sdk-host1
Version:  9.0.0
Edition:  cloud
CPUs:     8 across 1 socket(s)
Hardware: Dell Inc. PowerEdge R750
Serial:   XPSIM017RT
BIOS:     2.15.1
OK: host-info
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/host-info.sh`](../../cli/hosts-and-pools/host-info.sh)

```bash
# Host information.
#
# Read a host's software version, edition and CPU topology (sockets and cores).
#
# Run it:
#   ./workflows.sh host-info https://xenserver root "$password"

host_info() {
    h=$(first_host)
    echo "Host:    $(xe host-param-get uuid=$h param-name=name-label)"
    echo "Version: $(xe host-param-get uuid=$h param-name=software-version param-key=product_version)"
    echo "Edition: $(xe host-param-get uuid=$h param-name=edition)"
    # The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what you
    # quote to the hardware vendor, so it identifies this machine and not just its model.
    echo "Hardware: $(xe host-param-get uuid=$h param-name=bios-strings param-key=system-manufacturer) $(xe host-param-get uuid=$h param-name=bios-strings param-key=system-product-name)"
    echo "Serial:   $(xe host-param-get uuid=$h param-name=bios-strings param-key=system-serial-number)"
    echo "BIOS:     $(xe host-param-get uuid=$h param-name=bios-strings param-key=bios-version)"
    echo "OK: host-info"
}
```

<details><summary>Sample output</summary>

```text
Host:    sdk-host1
Version: 9.0.0
Edition: cloud
Hardware:  
Serial:   
BIOS:     
OK: host-info
```

</details>
