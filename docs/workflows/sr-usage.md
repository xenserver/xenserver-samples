<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Storage repository usage

Report each storage repository's used and total capacity, and rescan one.

Workflow `sr-usage`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Storage/Invoke-SrUsage.ps1`](../../powershell/Storage/Invoke-SrUsage.ps1)

```powershell
function Invoke-SrUsage {
    <#
    .SYNOPSIS
        Storage repository usage.
    .DESCRIPTION
        Report each storage repository's used and total capacity, and rescan one.
    .EXAMPLE
        Invoke-SrUsage -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    Get-XenSR | Sort-Object name_label | Where-Object { $_.physical_size -gt 0 } | ForEach-Object {
        $used = [long]($_.physical_utilisation / 1GB)
        $total = [long]($_.physical_size / 1GB)
        Write-Host "  $($_.name_label): $used / $total GiB used"
    }
    # A rescan refreshes an SR's utilisation from its backend.
    $scanMe = Get-XenSR | Where-Object { $_.physical_size -gt 0 } | Select-Object -First 1
    $scanMe | Invoke-XenSR -XenAction Scan
    Write-Host "OK: sr-usage"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  ISO library: 4 / 100 GiB used
  Local storage: 25 / 512 GiB used
  Local storage: 25 / 512 GiB used
  Shared NFS: 54 / 512 GiB used
OK: sr-usage
```

</details>

## xe CLI

Source: [`cli/storage/sr-usage.sh`](../../cli/storage/sr-usage.sh)

```bash
# Storage repository usage.
#
# Report each storage repository's used and total capacity, and rescan one.
#
# Run it:
#   ./workflows.sh sr-usage https://xenserver root "$password"

sr_usage() {
    echo "Storage:"
    # Built up here rather than piped straight from the loop, so scan_me survives it - every stage of a
    # pipeline runs in its own subshell, and a plain `for ... | sort` would lose it.
    scan_me="" lines=""
    for sr in $(each_csv "$(xe sr-list --minimal)"); do
        size=$(xe sr-param-get uuid=$sr param-name=physical-size)
        [ "$size" -gt 0 ] || continue   # skip ISO/DVD pseudo-SRs, which report no capacity
        [ -n "$scan_me" ] || scan_me=$sr
        util=$(xe sr-param-get uuid=$sr param-name=physical-utilisation)
        name=$(xe sr-param-get uuid=$sr param-name=name-label)
        lines+="$name"$'\t'"  $name: $((util / 1073741824)) / $((size / 1073741824)) GiB used"$'\n'
    done
    printf '%s' "$lines" | sort -t$'\t' -k1,1f | cut -f2-
    # A rescan refreshes an SR's utilisation from its backend.
    xe sr-scan uuid=$scan_me
    ok sr-usage
}
```

<details><summary>Example output</summary>

```text
Storage:
  iSCSI storage: 25 / 200 GiB used
  ISO library: 3 / 100 GiB used
  Local storage: 25 / 512 GiB used
  Local storage: 25 / 512 GiB used
  Shared NFS: 79 / 512 GiB used
OK: sr-usage
```

</details>

## Python

Source: [`python/storage/sr_usage.py`](../../python/storage/sr_usage.py)

```python
"""Storage repository usage.

Report each storage repository's used and total capacity, and rescan one.

Run it::

    sr_usage("https://xenserver", "root", password)
"""

from connection import connect


def sr_usage(url, username, password):
    """Report each real SR's used/total space, then rescan one to refresh its utilisation."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    srs = sorted(session.xenapi.SR.get_all_records().values(), key=lambda s: s["name_label"].lower())
    for sr in srs:
        if int(sr["physical_size"]) <= 0:
            continue  # skip ISO/DVD pseudo-SRs
        print("  %s: %d / %d GiB used"
              % (sr["name_label"],
                 int(sr["physical_utilisation"]) // GIB, int(sr["physical_size"]) // GIB))

    # A rescan refreshes an SR's utilisation from its backend.
    scan_me = next(ref for ref, r in session.xenapi.SR.get_all_records().items()
                   if int(r["physical_size"]) > 0)
    session.xenapi.SR.scan(scan_me)
    print("OK: sr-usage")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  ISO library: 3 / 100 GiB used
  Local storage: 25 / 512 GiB used
  Local storage: 25 / 512 GiB used
  Shared NFS: 54 / 512 GiB used
OK: sr-usage
```

</details>

## C# (.NET)

Source: [`csharp/Storage/SrUsage.cs`](../../csharp/Storage/SrUsage.cs)

```csharp
/// <summary>
/// Report each storage repository's used and total capacity, and rescan one.
/// </summary>
/// <example>
/// <code>
/// Workflows.SrUsage("https://xenserver", "root", password);
/// </code>
/// </example>
public static void SrUsage(string url, string user, string password)
{
    const long GiB = 1024L * 1024 * 1024;
    var session = Connect(url, user, password);
    foreach (var sr in SR.get_all_records(session).Values.OrderBy(s => s.name_label))
    {
        if (sr.physical_size <= 0) continue; // skip ISO/DVD pseudo-SRs
        Console.WriteLine($"  {sr.name_label}: {sr.physical_utilisation / GiB} / {sr.physical_size / GiB} GiB used");
    }
    // A rescan refreshes an SR's utilisation from its backend.
    var scanMe = SR.get_all_records(session).First(kv => kv.Value.physical_size > 0).Key;
    SR.scan(session, scanMe);
    Console.WriteLine("OK: sr-usage");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  ISO library: 3 / 100 GiB used
  Local storage: 25 / 512 GiB used
  Local storage: 25 / 512 GiB used
  Shared NFS: 58 / 512 GiB used
OK: sr-usage
```

</details>

## Go

Source: [`go/sr_usage.go`](../../go/sr_usage.go)

```go
package main

import (
	"fmt"
	"sort"
	"strings"

	"go/xenapi"
)

// srUsage - Storage repository usage.
//
// Report each storage repository's used and total capacity, and rescan one.
//
// Run it:
//
//	srUsage("https://xenserver", "root", password)
func srUsage(url, user, password string) {
	const GiB = 1024 * 1024 * 1024

	session := connect(url, user, password)
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)

	type namedSR struct {
		ref xenapi.SRRef
		rec xenapi.SRRecord
	}
	ordered := make([]namedSR, 0, len(srs))
	for ref, sr := range srs {
		ordered = append(ordered, namedSR{ref, sr})
	}
	sort.Slice(ordered, func(i, j int) bool {
		return strings.ToLower(ordered[i].rec.NameLabel) < strings.ToLower(ordered[j].rec.NameLabel)
	})

	var scanMe xenapi.SRRef
	haveScan := false
	for _, sr := range ordered {
		if sr.rec.PhysicalSize <= 0 { // skip ISO/DVD pseudo-SRs
			continue
		}
		fmt.Printf("  %s: %d / %d GiB used\n", sr.rec.NameLabel, sr.rec.PhysicalUtilisation/GiB, sr.rec.PhysicalSize/GiB)
		if !haveScan {
			scanMe, haveScan = sr.ref, true
		}
	}
	// A rescan refreshes an SR's utilisation from its backend.
	if haveScan {
		check(xenapi.SR.Scan(session, scanMe))
	}
	fmt.Println("OK: sr-usage")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  ISO library: 3 / 100 GiB used
  Local storage: 25 / 512 GiB used
  Local storage: 25 / 512 GiB used
  Shared NFS: 25 / 512 GiB used
OK: sr-usage
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/SrUsage.java`](../../java/src/main/java/com/xenserver/samples/storage/SrUsage.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class SrUsage {
    private SrUsage() {
    }

    /**
     * Storage repository usage.
     *
     * <p>Report each storage repository's used and total capacity, and rescan one.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * SrUsage.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        java.util.List<SR.Record> srs = new java.util.ArrayList<>(SR.getAllRecords(conn).values());
        srs.sort(java.util.Comparator.comparing((SR.Record s) -> s.nameLabel, String.CASE_INSENSITIVE_ORDER));
        for (SR.Record sr : srs) {
            if (sr.physicalSize <= 0) continue; // skip ISO/DVD pseudo-SRs
            System.out.println("  " + sr.nameLabel + ": " + sr.physicalUtilisation / GiB
                    + " / " + sr.physicalSize / GiB + " GiB used");
        }
        // A rescan refreshes an SR's utilisation from its backend.
        SR scanMe = null;
        for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet())
            if (e.getValue().physicalSize > 0) { scanMe = e.getKey(); break; }
        scanMe.scan(conn);
        System.out.println("OK: sr-usage");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  ISO library: 3 / 100 GiB used
  Local storage: 25 / 512 GiB used
  Local storage: 25 / 512 GiB used
  Shared NFS: 29 / 512 GiB used
OK: sr-usage
```

</details>
