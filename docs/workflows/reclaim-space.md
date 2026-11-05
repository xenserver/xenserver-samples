<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Reclaim freed space on a thin SR

Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable SR, pick a host with a live connection to it, and run the trim operation.

Workflow `reclaim-space`. [All workflows](README.md) · [Connecting](connecting.md)

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
    var session = Connect(url, user, password);
    // Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
    var trimTypes = SM.get_all_records(session).Values
        .Where(sm => sm.features.ContainsKey("SR_TRIM")).Select(sm => sm.type).ToHashSet();
    var sr = SR.get_all_records(session).Values
        .First(s => s.physical_size > 0 && trimTypes.Contains(s.type));
    // A host with a currently-attached PBD can reach the SR to run the plugin.
    var host = sr.PBDs.Select(r => PBD.get_record(session, r))
        .First(pbd => pbd.currently_attached).host;
    var args = new Dictionary<string, string> { ["sr_uuid"] = sr.uuid };
    var result = Host.call_plugin(session, host.opaque_ref, "trim", "do_trim", args);
    Console.WriteLine($"  reclaimed freed space on {sr.name_label}: {result}");
    // Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    if (result.Trim().ToLowerInvariant() != "true") throw new Exception($"trim plugin returned '{result}'");
    Console.WriteLine("OK: reclaim-space");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
  reclaimed freed space on iSCSI storage: True
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
    session = connect(url, username, password)
    # Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
    trim_types = set(sm["type"] for sm in session.xenapi.SM.get_all_records().values()
                     if "SR_TRIM" in sm["features"])
    sr = next(r for r in session.xenapi.SR.get_all_records().values()
              if r["type"] in trim_types and int(r["physical_size"]) > 0)
    # A host with a currently-attached PBD can reach the SR to run the plugin.
    host = next(pbd["host"] for pbd in
                (session.xenapi.PBD.get_record(ref) for ref in sr["PBDs"])
                if pbd["currently_attached"])
    result = session.xenapi.host.call_plugin(host, "trim", "do_trim", {"sr_uuid": sr["uuid"]})
    print("  reclaimed freed space on %s: %s" % (sr["name_label"], result))
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    assert result.strip().lower() == "true", "trim plugin returned %r" % result
    print("OK: reclaim-space")
    session.logout()
```

<details><summary>Example output</summary>

```text
  reclaimed freed space on iSCSI storage: True
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
        Connection conn = connect(url, user, password);
        try {
            // Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
            java.util.Set<String> trimTypes = new java.util.HashSet<>();
            for (SM.Record sm : SM.getAllRecords(conn).values())
                if (sm.features.containsKey("SR_TRIM")) trimTypes.add(sm.type);
            SR.Record sr = null;
            for (SR.Record r : SR.getAllRecords(conn).values())
                if (r.physicalSize > 0 && trimTypes.contains(r.type)) { sr = r; break; }
            // A host with a currently-attached PBD can reach the SR to run the plugin.
            Host host = null;
            for (PBD pbd : sr.PBDs) {
                PBD.Record pr = pbd.getRecord(conn);
                if (pr.currentlyAttached) { host = pr.host; break; }
            }
            java.util.Map<String, String> pargs = new java.util.HashMap<>();
            pargs.put("sr_uuid", sr.uuid);
            String result = host.callPlugin(conn, "trim", "do_trim", pargs);
            System.out.println("  reclaimed freed space on " + sr.nameLabel + ": " + result);
            // Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
            if (!"true".equalsIgnoreCase(result.trim()))
                throw new RuntimeException("trim plugin returned '" + result + "'");
            System.out.println("OK: reclaim-space");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
  reclaimed freed space on iSCSI storage: True
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
	session := connect(url, user, password)

	// Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
	sms, err := xenapi.SM.GetAllRecords(session)
	check(err)
	trimTypes := map[string]bool{}
	for _, sm := range sms {
		if _, ok := sm.Features["SR_TRIM"]; ok {
			trimTypes[sm.Type] = true
		}
	}

	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var sr xenapi.SRRecord
	found := false
	for _, r := range srs {
		if r.PhysicalSize > 0 && trimTypes[r.Type] {
			sr, found = r, true
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

	result, err := xenapi.Host.CallPlugin(session, host, "trim", "do_trim",
		map[string]string{"sr_uuid": sr.UUID})
	check(err)
	fmt.Printf("  reclaimed freed space on %s: %s\n", sr.NameLabel, result)
	// Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
	if strings.ToLower(strings.TrimSpace(result)) != "true" {
		panic("trim plugin returned " + result)
	}
	fmt.Println("OK: reclaim-space")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
  reclaimed freed space on iSCSI storage: True
OK: reclaim-space
```

</details>

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
    $result = $xenHost | Invoke-XenHost -XenAction CallPlugin -Plugin "trim" -Fn "do_trim" -Args @{ sr_uuid = $sr.uuid } -PassThru
    Write-Host "  reclaimed freed space on $($sr.name_label): $result"
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    if ($result.Trim().ToLowerInvariant() -ne "true") { throw "trim plugin returned '$result'" }
    Write-Host "OK: reclaim-space"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
  reclaimed freed space on iSCSI storage: True
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
    local sr candidate type pbd h name result
    # A thin-provisioned SR (local LVM here) can return space freed by deleted disks to the backend via
    # the trim plugin. Find one via its storage manager's SR_TRIM feature, instead of hard-coding a
    # type.
    sr=""
    for candidate in $(each_csv "$(xe sr-list --minimal)"); do
        type=$(xe sr-param-get uuid=$candidate param-name=type)
        [[ $(xe sm-list type=$type params=features --minimal) == *SR_TRIM* ]] || continue
        [ "$(xe sr-param-get uuid=$candidate param-name=physical-size)" -gt 0 ] || continue
        sr=$candidate; break
    done
    [ -n "$sr" ] || { echo "no trim-capable SR was found" >&2; exit 1; }

    # A host with a live (plugged) connection to the SR runs the plugin.
    pbd=$(first_csv "$(xe pbd-list sr-uuid=$sr currently-attached=true --minimal)")
    h=$(xe pbd-param-get uuid=$pbd param-name=host)
    name=$(xe sr-param-get uuid=$sr param-name=name-label)
    result=$(xe host-call-plugin host-uuid=$h plugin=trim fn=do_trim args:sr_uuid=$sr)
    echo "  reclaimed freed space on $name: $result"
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    [ "${result,,}" = "true" ] || { echo "trim failed: $result" >&2; exit 1; }
    echo "OK: reclaim-space"
}
```

<details><summary>Example output</summary>

```text
  reclaimed freed space on iSCSI storage: True
OK: reclaim-space
```

</details>
