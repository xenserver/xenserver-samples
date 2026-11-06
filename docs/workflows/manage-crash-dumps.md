<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Clear a host's crash dumps

Find the crash dumps a host kept after a failure, report how big and how old they are, then delete them to free the space.

Workflow `manage-crash-dumps`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ManageCrashDumps.ps1`](../../powershell/HostsAndPools/Invoke-ManageCrashDumps.ps1)

```powershell
function Invoke-ManageCrashDumps {
    <#
    .SYNOPSIS
        Clear a host's crash dumps.
    .DESCRIPTION
        Find the crash dumps a host kept after a failure, report how big and how old they are, then delete
        them to free the space.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # When a host crashes it writes a dump to its local disk and keeps it. They are large, nothing cleans
    # them up, and a host that has crashed more than once accumulates them - so clearing them once support
    # has what it needs is ordinary housekeeping. They belong to the host that wrote them, so clear them a
    # host at a time.
    $xenHost = Get-XenHost | Where-Object { $_.crashdumps.Count -gt 0 } | Select-Object -First 1
    if (-not $xenHost) {
        Write-Host "No crash dumps in this pool - nothing to clear."
        Write-Host "OK: manage-crash-dumps"
        $session | Disconnect-XenServer
        return
    }

    $dumps = @($xenHost.crashdumps | ForEach-Object { Get-XenHostCrashdump -Ref $_ })
    Write-Host "$($xenHost.name_label) has $($dumps.Count) crash dump(s)"
    $total = 0
    foreach ($dump in $dumps) {
        $total += $dump.size
        Write-Host ("  {0:yyyyMMdd'T'HH:mm:ss'Z'}  {1}" -f $dump.timestamp, (Format-Mib $dump.size))
    }
    Write-Host "  $(Format-Mib $total) in total"

    # Deleting a dump frees the space on the host; the host itself is untouched.
    $dumps | Remove-XenHostCrashdump
    Write-Host "  cleared:  $($xenHost.name_label) now has $((Get-XenHost -Ref $xenHost).crashdumps.Count)"

    Write-Host "OK: manage-crash-dumps"
    $session | Disconnect-XenServer
}

function Format-Mib {
    param([long]$Size)
    "{0} MiB" -f [math]::Floor($Size / 1MB)
}
```

<details><summary>Example output</summary>

```text
sdk-host1 has 3 crash dump(s)
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  768 MiB in total
  cleared:  sdk-host1 now has 0
OK: manage-crash-dumps
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/manage-crash-dumps.sh`](../../cli/hosts-and-pools/manage-crash-dumps.sh)

```bash
# Clear a host's crash dumps.
#
# Find the crash dumps a host kept after a failure, report how big and how old they are, then delete them to
# free the space.
#
# Run it:
#   ./workflows.sh manage-crash-dumps https://xenserver root "$password"

manage_crash_dumps() {
    # A host that crashes writes a dump to its local disk and keeps it. They are large and nothing cleans
    # them up, so clearing them once support has what it needs is ordinary housekeeping. They belong to
    # the host that wrote them, so clear them a host at a time.
    target=""
    for h in $(each_csv "$(xe host-list --minimal)"); do
        if [ -n "$(xe host-crashdump-list host-uuid=$h --minimal)" ]; then target=$h; break; fi
    done
    if [ -z "$target" ]; then
        echo "No crash dumps in this pool - nothing to clear."
        echo "OK: manage-crash-dumps"
        return
    fi

    dumps=$(xe host-crashdump-list host-uuid=$target --minimal)
    echo "$(xe host-param-get uuid=$target param-name=name-label) has $(count_csv "$dumps") crash dump(s)"
    total=0
    for d in $(each_csv "$dumps"); do
        size=$(xe host-crashdump-param-get uuid=$d param-name=size)
        total=$((total + size))
        echo "  $(xe host-crashdump-param-get uuid=$d param-name=timestamp)  $((size / 1048576)) MiB"
    done
    echo "  $((total / 1048576)) MiB in total"

    # Deleting a dump frees the space on the host; the host itself is untouched.
    for d in $(each_csv "$dumps"); do xe host-crashdump-destroy uuid=$d; done
    echo "  cleared:  $(xe host-param-get uuid=$target param-name=name-label) now has $(count_csv "$(xe host-crashdump-list host-uuid=$target --minimal)")"
    echo "OK: manage-crash-dumps"
}
```

<details><summary>Example output</summary>

```text
sdk-host1 has 3 crash dump(s)
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  768 MiB in total
  cleared:  sdk-host1 now has 0
OK: manage-crash-dumps
```

</details>

## Python

Source: [`python/hosts_and_pools/manage_crash_dumps.py`](../../python/hosts_and_pools/manage_crash_dumps.py)

```python
"""Clear a host's crash dumps.

Find the crash dumps a host kept after a failure, report how big and how old they are, then delete
them to free the space.
"""

from connection import connect


def manage_crash_dumps(url, username, password):
    """Find and delete the crash dumps a host kept after a failure.

    When a host crashes it writes a dump to its local disk and keeps it. They are large, they
    are never cleaned up on their own, and on a host that has crashed more than once they add
    up -- so clearing them once support has what it needs is ordinary housekeeping."""
    session = connect(url, username, password)
    x = session.xenapi

    # Crash dumps belong to the host that wrote them, so clear them a host at a time.
    host = next((h for h in x.host.get_all() if x.host.get_crashdumps(h)), None)
    if host is None:
        print("No crash dumps in this pool -- nothing to clear.")
        print("OK: manage-crash-dumps")
        session.logout()
        return

    dumps = x.host.get_crashdumps(host)
    total = 0
    print("%s has %d crash dump(s)" % (x.host.get_name_label(host), len(dumps)))
    for ref in dumps:
        record = x.host_crashdump.get_record(ref)
        total += int(record["size"])
        print("  %s  %s" % (record["timestamp"], mib(record["size"])))
    print("  %s in total" % mib(total))

    # Deleting a dump frees the space on the host; the host itself is untouched.
    for ref in dumps:
        x.host_crashdump.destroy(ref)
    print("  cleared:  %s now has %d"
          % (x.host.get_name_label(host), len(x.host.get_crashdumps(host))))

    print("OK: manage-crash-dumps")
    session.logout()


def mib(size):
    return "%d MiB" % (int(size) // (1024 * 1024))
```

<details><summary>Example output</summary>

```text
sdk-host1 has 3 crash dump(s)
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  768 MiB in total
  cleared:  sdk-host1 now has 0
OK: manage-crash-dumps
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/ManageCrashDumps.cs`](../../csharp/HostsAndPools/ManageCrashDumps.cs)

```csharp
/// <summary>
/// Find the crash dumps a host kept after a failure, report how big and how old they are, then delete
/// them to free the space.
/// </summary>
public static void ManageCrashDumps(string url, string user, string password)
{
    var session = Connect(url, user, password);

    // When a host crashes it writes a dump to its local disk and keeps it. They are large, nothing
    // cleans them up, and a host that has crashed more than once accumulates them — so clearing them
    // once support has what it needs is ordinary housekeeping. They belong to the host that wrote
    // them, so clear them a host at a time.
    var host = Host.get_all(session)
        .FirstOrDefault(h => Host.get_crashdumps(session, h).Count > 0);
    if (host == null)
    {
        Console.WriteLine("No crash dumps in this pool — nothing to clear.");
        Console.WriteLine("OK: manage-crash-dumps");
        session.logout();
        return;
    }

    var dumps = Host.get_crashdumps(session, host);
    long total = 0;
    Console.WriteLine($"{Host.get_name_label(session, host)} has {dumps.Count} crash dump(s)");
    foreach (var dump in dumps)
    {
        var record = Host_crashdump.get_record(session, dump);
        total += record.size;
        Console.WriteLine($"  {record.timestamp:yyyyMMdd'T'HH:mm:ss'Z'}  {Mib(record.size)}");
    }
    Console.WriteLine($"  {Mib(total)} in total");

    // Deleting a dump frees the space on the host; the host itself is untouched.
    foreach (var dump in dumps) Host_crashdump.destroy(session, dump);
    Console.WriteLine($"  cleared:  {Host.get_name_label(session, host)} now has "
                      + Host.get_crashdumps(session, host).Count);

    Console.WriteLine("OK: manage-crash-dumps");
    session.logout();
}

private static string Mib(long size) => $"{size / (1024 * 1024)} MiB";
```

<details><summary>Example output</summary>

```text
sdk-host1 has 3 crash dump(s)
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  768 MiB in total
  cleared:  sdk-host1 now has 0
OK: manage-crash-dumps
```

</details>

## Go

Source: [`go/manage_crash_dumps.go`](../../go/manage_crash_dumps.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// manageCrashDumps - Clear a host's crash dumps.
//
// Find the crash dumps a host kept after a failure, report how big and how old they are, then
// delete them to free the space.
func manageCrashDumps(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	// When a host crashes it writes a dump to its local disk and keeps it. They are large, nothing cleans
	// them up, and a host that has crashed more than once accumulates them - so clearing them once support
	// has what it needs is ordinary housekeeping. They belong to the host that wrote them, so clear them a
	// host at a time.
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	var host xenapi.HostRef
	var dumps []xenapi.HostCrashdumpRef
	for _, h := range hosts {
		d, err := xenapi.Host.GetCrashdumps(session, h)
		check(err)
		if len(d) > 0 {
			host, dumps = h, d
			break
		}
	}
	if len(dumps) == 0 {
		fmt.Println("No crash dumps in this pool - nothing to clear.")
		fmt.Println("OK: manage-crash-dumps")
		return
	}

	name, _ := xenapi.Host.GetNameLabel(session, host)
	fmt.Printf("%s has %d crash dump(s)\n", name, len(dumps))
	var total int64
	for _, dump := range dumps {
		record, err := xenapi.HostCrashdump.GetRecord(session, dump)
		check(err)
		total += record.Size
		fmt.Printf("  %s  %s\n", record.Timestamp.Format("20060102T15:04:05Z"), mib(record.Size))
	}
	fmt.Printf("  %s in total\n", mib(total))

	// Deleting a dump frees the space on the host; the host itself is untouched.
	for _, dump := range dumps {
		check(xenapi.HostCrashdump.Destroy(session, dump))
	}
	left, _ := xenapi.Host.GetCrashdumps(session, host)
	fmt.Printf("  cleared:  %s now has %d\n", name, len(left))

	fmt.Println("OK: manage-crash-dumps")
}

func mib(size int64) string { return fmt.Sprintf("%d MiB", size/(1024*1024)) }
```

<details><summary>Example output</summary>

```text
sdk-host2 has 3 crash dump(s)
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  768 MiB in total
  cleared:  sdk-host2 now has 0
OK: manage-crash-dumps
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ManageCrashDumps.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ManageCrashDumps.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.HostCrashdump;
import com.xensource.xenapi.Session;

import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageCrashDumps {
    private ManageCrashDumps() {
    }

    /**
     * Clear a host's crash dumps.
     *
     * <p>Find the crash dumps a host kept after a failure, report how big and how old they are, then
     * delete them to free the space.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // When a host crashes it writes a dump to its local disk and keeps it. They are large,
            // nothing cleans them up, and a host that has crashed more than once accumulates them - so
            // clearing them once support has what it needs is ordinary housekeeping. They belong to the
            // host that wrote them, so clear them a host at a time.
            Host host = null;
            Set<HostCrashdump> dumps = null;
            for (Host h : Host.getAll(conn)) {
                Set<HostCrashdump> d = h.getCrashdumps(conn);
                if (!d.isEmpty()) { host = h; dumps = d; break; }
            }
            if (host == null) {
                System.out.println("No crash dumps in this pool - nothing to clear.");
                System.out.println("OK: manage-crash-dumps");
                return;
            }

            System.out.printf("%s has %d crash dump(s)%n", host.getNameLabel(conn), dumps.size());
            long total = 0;
            java.text.SimpleDateFormat stamp = new java.text.SimpleDateFormat("yyyyMMdd'T'HH:mm:ss'Z'");
            stamp.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
            for (HostCrashdump dump : dumps) {
                HostCrashdump.Record record = dump.getRecord(conn);
                total += record.size;
                System.out.printf("  %s  %s%n", stamp.format(record.timestamp), mib(record.size));
            }
            System.out.printf("  %s in total%n", mib(total));

            // Deleting a dump frees the space on the host; the host itself is untouched.
            for (HostCrashdump dump : dumps) dump.destroy(conn);
            System.out.printf("  cleared:  %s now has %d%n",
                host.getNameLabel(conn), host.getCrashdumps(conn).size());

            System.out.println("OK: manage-crash-dumps");
        } finally {
            Session.logout(conn);
        }
    }

    private static String mib(long size) { return (size / (1024 * 1024)) + " MiB"; }
}
```

<details><summary>Example output</summary>

```text
sdk-host2 has 3 crash dump(s)
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  20260101T09:00:00Z  256 MiB
  768 MiB in total
  cleared:  sdk-host2 now has 0
OK: manage-crash-dumps
```

</details>
