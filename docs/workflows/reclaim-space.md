<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Reclaim freed space on a thin SR

Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable SR, pick a host with a live connection to it, and run the trim operation.

Workflow `reclaim-space`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Storage/Invoke-ReclaimSpace.ps1`](../../powershell/Storage/Invoke-ReclaimSpace.ps1)

```powershell
function Invoke-ReclaimSpace {
    <#
    .SYNOPSIS
        Reclaim freed space on a thin SR.
    .DESCRIPTION
        Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable
        SR, pick a host with a live connection to it, and run the trim operation.
    .EXAMPLE
        Invoke-ReclaimSpace -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
    $trimTypes = @(Get-XenSM | Where-Object { $_.features.ContainsKey("SR_TRIM") } | ForEach-Object { $_.type })
    $sr = Get-XenSR | Where-Object { $_.physical_size -gt 0 -and $trimTypes -contains $_.type } | Select-Object -First 1
    # A host with a currently-attached PBD can reach the SR to run the plugin.
    $pbd = $sr.PBDs | ForEach-Object { Get-XenPBD -Ref $_ } | Where-Object { $_.currently_attached } | Select-Object -First 1
    $xenHost = Get-XenHost -Ref $pbd.host

    $used = [long]($sr.physical_utilisation / 1GB)
    $total = [long]($sr.physical_size / 1GB)
    Write-Host "  $($sr.name_label): $used / $total GiB used"

    $result = $xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin "trim" -Fn "do_trim" -Args @{ sr_uuid = $sr.uuid } -PassThru
    Write-Host "  reclaimed freed space on $($sr.name_label): $result"
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    if ($result.Trim().ToLowerInvariant() -ne "true") { throw "trim plugin returned '$result'" }

    # Rescan to refresh utilisation from the backend, the same way Invoke-SrUsage does, before reporting it.
    $sr | Invoke-XenSR -XenAction Scan
    $usedAfter = [long]((Get-XenSR -Ref $sr).physical_utilisation / 1GB)
    Write-Host "  $($sr.name_label): $usedAfter / $total GiB used"
    Write-Host "OK: reclaim-space"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  reclaimed freed space on iSCSI storage: True
  iSCSI storage: 22 / 200 GiB used
OK: reclaim-space
```

</details>

## xe CLI

Source: [`cli/storage/reclaim-space.sh`](../../cli/storage/reclaim-space.sh)

```bash
# Reclaim freed space on a thin SR.
#
# Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable SR, pick
# a host with a live connection to it, and run the trim operation.
#
# Run it:
#   ./workflows.sh reclaim-space https://xenserver root "$password"

reclaim_space() {
    local sr candidate type pbd h name result size before after
    # A thin-provisioned SR (local LVM here) can return space freed by deleted disks to the backend via
    # the trim plugin. Find one via its storage manager's SR_TRIM feature, instead of hard-coding a
    # type.
    sr=""
    for candidate in $(each_csv "$(remote_xe sr-list --minimal)"); do
        type=$(remote_xe sr-param-get uuid=$candidate param-name=type)
        [[ $(remote_xe sm-list type=$type params=features --minimal) == *SR_TRIM* ]] || continue
        [ "$(remote_xe sr-param-get uuid=$candidate param-name=physical-size)" -gt 0 ] || continue
        sr=$candidate; break
    done
    [ -n "$sr" ] || { echo "no trim-capable SR was found" >&2; exit 1; }

    # A host with a live (plugged) connection to the SR runs the plugin.
    pbd=$(first_csv "$(remote_xe pbd-list sr-uuid=$sr currently-attached=true --minimal)")
    h=$(remote_xe pbd-param-get uuid=$pbd param-name=host)
    name=$(remote_xe sr-param-get uuid=$sr param-name=name-label)
    size=$(remote_xe sr-param-get uuid=$sr param-name=physical-size)
    before=$(remote_xe sr-param-get uuid=$sr param-name=physical-utilisation)
    echo "  $name: $((before / 1073741824)) / $((size / 1073741824)) GiB used"

    result=$(remote_xe host-call-plugin host-uuid=$h plugin=trim fn=do_trim args:sr_uuid=$sr)
    echo "  reclaimed freed space on $name: $result"
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    [ "${result,,}" = "true" ] || { echo "trim failed: $result" >&2; exit 1; }

    # Rescan to refresh utilisation from the backend, the same way sr-usage does, before reporting it.
    remote_xe sr-scan uuid=$sr
    after=$(remote_xe sr-param-get uuid=$sr param-name=physical-utilisation)
    echo "  $name: $((after / 1073741824)) / $((size / 1073741824)) GiB used"
    ok reclaim-space
}
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  reclaimed freed space on iSCSI storage: True
  iSCSI storage: 22 / 200 GiB used
OK: reclaim-space
```

</details>

## Python

Source: [`python/storage/reclaim_space.py`](../../python/storage/reclaim_space.py)

```python
"""Reclaim freed space on a thin SR.

Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable
SR, pick a host with a live connection to it, and run the trim operation.
"""

from connection import connect


def reclaim_space(url, username, password):
    """Reclaim space freed by deleted disks on a thin-provisioned SR ("Reclaim freed space").

    A thin SR supports the trim/do_trim host plugin. Find one via its storage manager's
    SR_TRIM feature, pick a host with a live (currently-attached) connection to it, and run
    the plugin.
    """
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    # Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
    trim_types = set(sm["type"] for sm in session.xenapi.SM.get_all_records().values()
                     if "SR_TRIM" in sm["features"])
    sr_ref, sr = next((ref, r) for ref, r in session.xenapi.SR.get_all_records().items()
                      if r["type"] in trim_types and int(r["physical_size"]) > 0)
    # A host with a currently-attached PBD can reach the SR to run the plugin.
    host = next(pbd["host"] for pbd in
                (session.xenapi.PBD.get_record(ref) for ref in sr["PBDs"])
                if pbd["currently_attached"])

    print("  %s: %d / %d GiB used"
          % (sr["name_label"], int(sr["physical_utilisation"]) // GIB, int(sr["physical_size"]) // GIB))

    result = session.xenapi.host.call_plugin(host, "trim", "do_trim", {"sr_uuid": sr["uuid"]})
    print("  reclaimed freed space on %s: %s" % (sr["name_label"], result))
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    assert result.strip().lower() == "true", "trim plugin returned %r" % result

    # Rescan to refresh utilisation from the backend, the same way sr_usage does, before reporting it.
    session.xenapi.SR.scan(sr_ref)
    used_after = int(session.xenapi.SR.get_physical_utilisation(sr_ref))
    print("  %s: %d / %d GiB used" % (sr["name_label"], used_after // GIB, int(sr["physical_size"]) // GIB))
    print("OK: reclaim-space")
    session.logout()
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  reclaimed freed space on iSCSI storage: True
  iSCSI storage: 22 / 200 GiB used
OK: reclaim-space
```

</details>

## C# (.NET)

Source: [`csharp/Storage/ReclaimSpace.cs`](../../csharp/Storage/ReclaimSpace.cs)

```csharp
/// <summary>
/// Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable SR,
/// pick a host with a live connection to it, and run the trim operation.
/// </summary>
/// <example>
/// <code>
/// Workflows.ReclaimSpace("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ReclaimSpace(string url, string user, string password)
{
    const long GiB = 1024L * 1024 * 1024;
    var session = Connect(url, user, password);
    // Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
    var trimTypes = SM.get_all_records(session).Values
        .Where(sm => sm.features.ContainsKey("SR_TRIM")).Select(sm => sm.type).ToHashSet();
    var srEntry = SR.get_all_records(session)
        .First(kv => kv.Value.physical_size > 0 && trimTypes.Contains(kv.Value.type));
    var srRef = srEntry.Key;
    var sr = srEntry.Value;
    // A host with a currently-attached PBD can reach the SR to run the plugin.
    var host = sr.PBDs.Select(r => PBD.get_record(session, r))
        .First(pbd => pbd.currently_attached).host;

    Console.WriteLine($"  {sr.name_label}: {sr.physical_utilisation / GiB} / {sr.physical_size / GiB} GiB used");

    var args = new Dictionary<string, string> { ["sr_uuid"] = sr.uuid };
    var result = Host.call_plugin(session, host, "trim", "do_trim", args);
    Console.WriteLine($"  reclaimed freed space on {sr.name_label}: {result}");
    // Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    if (result.Trim().ToLowerInvariant() != "true") throw new InvalidOperationException($"trim plugin returned '{result}'");

    // Rescan to refresh utilisation from the backend, the same way SrUsage does, before reporting it.
    SR.scan(session, srRef);
    var usedAfter = SR.get_physical_utilisation(session, srRef);
    Console.WriteLine($"  {sr.name_label}: {usedAfter / GiB} / {sr.physical_size / GiB} GiB used");
    Console.WriteLine("OK: reclaim-space");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  reclaimed freed space on iSCSI storage: True
  iSCSI storage: 22 / 200 GiB used
OK: reclaim-space
```

</details>

## Go

Source: [`go/reclaim_space.go`](../../go/reclaim_space.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// reclaimSpace - Reclaim freed space on a thin SR.
//
// Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a
// trim-capable SR, pick a host with a live connection to it, and run the trim operation.
func reclaimSpace(url, user, password string) {
	const GiB = 1024 * 1024 * 1024

	session := connect(url, user, password)
	defer session.Logout()

	// Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
	sms, err := xenapi.SM.GetAllRecords(session)
	check(err)
	trimTypes := map[string]bool{}
	for _, sm := range sms {
		if _, ok := sm.Features["SR_TRIM"]; ok {
			trimTypes[sm.Type] = true
		}
	}

	// SR.GetAll keeps the server's order (GetAllRecords returns a map, which Go ranges in random order),
	// so this takes the same SR as the other languages.
	srRefs, err := xenapi.SR.GetAll(session)
	check(err)
	var srRef xenapi.SRRef
	var sr xenapi.SRRecord
	found := false
	for _, ref := range srRefs {
		r, err := xenapi.SR.GetRecord(session, ref)
		check(err)
		if r.PhysicalSize > 0 && trimTypes[r.Type] {
			srRef, sr, found = ref, r, true
			break
		}
	}
	if !found {
		panic("no trim-capable SR found")
	}

	// A host with a currently-attached PBD can reach the SR to run the plugin.
	var host xenapi.HostRef
	for _, pbdRef := range sr.PBDs {
		pbd, err := xenapi.PBD.GetRecord(session, pbdRef)
		check(err)
		if pbd.CurrentlyAttached {
			host = pbd.Host
			break
		}
	}

	fmt.Printf("  %s: %d / %d GiB used\n", sr.NameLabel, sr.PhysicalUtilisation/GiB, sr.PhysicalSize/GiB)

	result, err := xenapi.Host.CallPlugin(session, host, "trim", "do_trim",
		map[string]string{"sr_uuid": sr.UUID})
	check(err)
	fmt.Printf("  reclaimed freed space on %s: %s\n", sr.NameLabel, result)
	// Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
	if strings.ToLower(strings.TrimSpace(result)) != "true" {
		panic("trim plugin returned " + result)
	}

	// Rescan to refresh utilisation from the backend, the same way srUsage does, before reporting it.
	check(xenapi.SR.Scan(session, srRef))
	usedAfter, err := xenapi.SR.GetPhysicalUtilisation(session, srRef)
	check(err)
	fmt.Printf("  %s: %d / %d GiB used\n", sr.NameLabel, usedAfter/GiB, sr.PhysicalSize/GiB)
	fmt.Println("OK: reclaim-space")
}
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  reclaimed freed space on iSCSI storage: True
  iSCSI storage: 22 / 200 GiB used
OK: reclaim-space
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/ReclaimSpace.java`](../../java/src/main/java/com/xenserver/samples/storage/ReclaimSpace.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.SM;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ReclaimSpace {
    private ReclaimSpace() {
    }

    /**
     * Reclaim freed space on a thin SR.
     *
     * <p>Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a
     * trim-capable SR, pick a host with a live connection to it, and run the trim operation.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ReclaimSpace.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        try {
            // Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
            java.util.Set<String> trimTypes = new java.util.HashSet<>();
            for (SM.Record sm : SM.getAllRecords(conn).values())
                if (sm.features.containsKey("SR_TRIM")) trimTypes.add(sm.type);
            SR sr = null;
            SR.Record srRecord = null;
            for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet())
                if (e.getValue().physicalSize > 0 && trimTypes.contains(e.getValue().type)) {
                    sr = e.getKey();
                    srRecord = e.getValue();
                    break;
                }
            // A host with a currently-attached PBD can reach the SR to run the plugin.
            Host host = null;
            for (PBD pbd : srRecord.PBDs) {
                PBD.Record pr = pbd.getRecord(conn);
                if (pr.currentlyAttached) { host = pr.host; break; }
            }

            System.out.println("  " + srRecord.nameLabel + ": " + srRecord.physicalUtilisation / GiB
                    + " / " + srRecord.physicalSize / GiB + " GiB used");

            java.util.Map<String, String> pargs = new java.util.HashMap<>();
            pargs.put("sr_uuid", srRecord.uuid);
            String result = host.callPlugin(conn, "trim", "do_trim", pargs);
            System.out.println("  reclaimed freed space on " + srRecord.nameLabel + ": " + result);
            // Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
            if (!"true".equalsIgnoreCase(result.trim()))
                throw new IllegalStateException("trim plugin returned '" + result + "'");

            // Rescan to refresh utilisation from the backend, the same way SrUsage does, before reporting it.
            sr.scan(conn);
            long usedAfter = sr.getRecord(conn).physicalUtilisation;
            System.out.println("  " + srRecord.nameLabel + ": " + usedAfter / GiB
                    + " / " + srRecord.physicalSize / GiB + " GiB used");
            System.out.println("OK: reclaim-space");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
  iSCSI storage: 25 / 200 GiB used
  reclaimed freed space on iSCSI storage: True
  iSCSI storage: 22 / 200 GiB used
OK: reclaim-space
```

</details>
