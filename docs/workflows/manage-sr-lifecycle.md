<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Detach, reattach and forget storage

Take a storage repository offline and bring it back: disconnect it from every host, reconnect and rescan it, then disconnect it once more and forget it for good.

Workflow `manage-sr-lifecycle`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Storage/Invoke-ManageSrLifecycle.ps1`](../../powershell/Storage/Invoke-ManageSrLifecycle.ps1)

```powershell
function Invoke-ManageSrLifecycle {
    <#
    .SYNOPSIS
        Detach, reattach and forget storage.
    .DESCRIPTION
        Take a storage repository offline and bring it back: disconnect it from every host, reconnect and
        rescan it, then disconnect it once more and forget it for good.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$NfsServer = "192.0.2.10",
        [string]$NfsPath = "/export/spare"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # There is no "detach" call on an SR. A shared SR is joined to each host by one PBD - a physical
    # block device - and detaching the SR means unplugging every one of them. That is why an SR can be
    # attached on some hosts and not others, and why a repair action exists at all: it plugs back the
    # PBDs that are missing.
    $xenHost = Get-XenHost | Select-Object -First 1
    $sr = New-XenSR -XenHost $xenHost -PhysicalSize 0 `
        -DeviceConfig @{ server = $NfsServer; serverpath = $NfsPath; nfsversion = "3" } `
        -NameLabel "sdk-example-lifecycle" -NameDescription "SR used by the SDK lifecycle example" `
        -Type "nfs" -ContentType "user" -Shared $true -PassThru

    $pbds = @($sr.PBDs | ForEach-Object { Get-XenPBD -Ref $_.opaque_ref })
    Write-Host ("{0}: connected on {1} of {2} host(s)" -f
        $sr.name_label, (Measure-AttachedPbd $pbds), $pbds.Count)

    $pbds | Invoke-XenPBD -XenAction Unplug
    Write-Host ("  detached:   connected on {0} host(s)" -f (Measure-AttachedPbd $pbds))

    # Plugging them back is exactly what a repair does.
    $pbds | Invoke-XenPBD -XenAction Plug
    Write-Host ("  reattached: connected on {0} host(s)" -f (Measure-AttachedPbd $pbds))

    $sr | Invoke-XenSR -XenAction Scan
    Write-Host ("  rescanned:  {0} disk(s)" -f (Get-XenSR -Ref $sr.opaque_ref).VDIs.Count)

    # Forgetting drops the pool's record of the SR but leaves the storage itself untouched, so the same
    # export can be introduced again later. Detach before forgetting: a connected SR is still in use.
    $pbds | Invoke-XenPBD -XenAction Unplug
    $sr | Invoke-XenSR -XenAction Forget
    Write-Host "  forgotten"
    Write-Host "OK: manage-sr-lifecycle"
    $session | Disconnect-XenServer
}

function Measure-AttachedPbd {
    <#
    .SYNOPSIS
        How many of these connections are currently live.
    .DESCRIPTION
        Re-read each one: the cached records were fetched before the plug state changed.
    #>
    param($Pbds)
    @($Pbds | Where-Object { (Get-XenPBD -Ref $_.opaque_ref).currently_attached }).Count
}
```

<details><summary>Example output</summary>

```text
sdk-example-lifecycle: connected on 2 of 2 host(s)
  detached:   connected on 0 host(s)
  reattached: connected on 2 host(s)
  rescanned:  0 disk(s)
  forgotten
OK: manage-sr-lifecycle
```

</details>

## xe CLI

Source: [`cli/storage/manage-sr-lifecycle.sh`](../../cli/storage/manage-sr-lifecycle.sh)

```bash
# Detach, reattach and forget storage.
#
# Take a storage repository offline and bring it back: disconnect it from every host, reconnect and rescan it,
# then disconnect it once more and forget it for good.
#
# Run it:
#   ./workflows.sh manage-sr-lifecycle https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   nfs_server (192.0.2.10)
#   nfs_path (/export/spare)

manage_sr_lifecycle() {
    sr=$(xe sr-create name-label=xe-example-lifecycle type=nfs content-type=user shared=true \
        device-config:server="$(param nfs_server 192.0.2.10)" \
        device-config:serverpath="$(param nfs_path /export/spare)" device-config:nfsversion=3)

    # There is no sr-detach: a shared SR is joined to each host by one PBD, and detaching the SR means
    # unplugging every one of them. That is why an SR can be attached on some hosts and not others.
    pbds=$(xe pbd-list sr-uuid=$sr --minimal)
    echo "$(xe sr-param-get uuid=$sr param-name=name-label): connected on $(count_attached_pbd "$pbds") of $(count_csv "$pbds") host(s)"

    for pbd in $(each_csv "$pbds"); do xe pbd-unplug uuid=$pbd; done
    echo "  detached:   connected on $(count_attached_pbd "$pbds") host(s)"

    # Plugging them back is exactly what a repair does.
    for pbd in $(each_csv "$pbds"); do xe pbd-plug uuid=$pbd; done
    echo "  reattached: connected on $(count_attached_pbd "$pbds") host(s)"

    xe sr-scan uuid=$sr
    echo "  rescanned:  $(count_csv "$(xe vdi-list sr-uuid=$sr --minimal)") disk(s)"

    # Forgetting drops the pool's record of the SR but leaves the storage itself untouched, so the same
    # export can be introduced again later. Detach before forgetting: a connected SR is still in use.
    for pbd in $(each_csv "$pbds"); do xe pbd-unplug uuid=$pbd; done
    xe sr-forget uuid=$sr
    echo "  forgotten"
    echo "OK: manage-sr-lifecycle"
}

# How many of the given PBDs are currently attached.
count_attached_pbd() {
    local n=0
    for pbd in $(each_csv "$1"); do
        if [ "$(xe pbd-param-get uuid=$pbd param-name=currently-attached)" = "true" ]; then n=$((n + 1)); fi
    done
    echo $n
}
```

<details><summary>Example output</summary>

```text
xe-example-lifecycle: connected on 2 of 2 host(s)
  detached:   connected on 0 host(s)
  reattached: connected on 2 host(s)
  rescanned:  0 disk(s)
  forgotten
OK: manage-sr-lifecycle
```

</details>

## Python

Source: [`python/storage/manage_sr_lifecycle.py`](../../python/storage/manage_sr_lifecycle.py)

```python
"""Detach, reattach and forget storage.

Take a storage repository offline and bring it back: disconnect it from every host, reconnect and
rescan it, then disconnect it once more and forget it for good.
"""

from connection import connect


def manage_sr_lifecycle(url, username, password, nfs_server="192.0.2.10", nfs_path="/export/spare"):
    """Take a storage repository offline, bring it back, then forget it.

    There is no "detach" call on an SR. A shared SR is joined to each host by one PBD -- a
    physical block device -- and detaching the SR means unplugging every one of them. That
    is why an SR can be attached on some hosts and not others, and why a repair action
    exists at all: it plugs back the PBDs that are missing."""
    session = connect(url, username, password)
    x = session.xenapi

    host = x.host.get_all()[0]
    sr = x.SR.create(host, {"server": nfs_server, "serverpath": nfs_path, "nfsversion": "3"},
                     "0", "sdk-example-lifecycle", "SR used by the SDK lifecycle example",
                     "nfs", "user", True, {})
    pbds = x.SR.get_PBDs(sr)
    print("%s: connected on %d of %d host(s)"
          % (x.SR.get_name_label(sr), attached_pbds(x, pbds), len(pbds)))

    for pbd in pbds:
        x.PBD.unplug(pbd)
    print("  detached:   connected on %d host(s)" % attached_pbds(x, pbds))

    # Plugging them back is exactly what a repair does.
    for pbd in pbds:
        x.PBD.plug(pbd)
    print("  reattached: connected on %d host(s)" % attached_pbds(x, pbds))

    x.SR.scan(sr)
    print("  rescanned:  %d disk(s)" % len(x.SR.get_VDIs(sr)))

    # Forgetting drops the pool's record of the SR but leaves the storage itself untouched,
    # so the same export can be introduced again later. Detach before forgetting: a
    # connected SR is still in use.
    for pbd in pbds:
        x.PBD.unplug(pbd)
    x.SR.forget(sr)
    print("  forgotten")
    print("OK: manage-sr-lifecycle")
    session.logout()


def attached_pbds(x, pbds):
    """How many of these connections are currently live."""
    return sum(1 for pbd in pbds if x.PBD.get_currently_attached(pbd))
```

<details><summary>Example output</summary>

```text
sdk-example-lifecycle: connected on 2 of 2 host(s)
  detached:   connected on 0 host(s)
  reattached: connected on 2 host(s)
  rescanned:  0 disk(s)
  forgotten
OK: manage-sr-lifecycle
```

</details>

## C# (.NET)

Source: [`csharp/Storage/ManageSrLifecycle.cs`](../../csharp/Storage/ManageSrLifecycle.cs)

```csharp
/// <summary>
/// Take a storage repository offline and bring it back: disconnect it from every host, reconnect and
/// rescan it, then disconnect it once more and forget it for good.
/// </summary>
public static void ManageSrLifecycle(string url, string user, string password,
    string nfsServer = "192.0.2.10", string nfsPath = "/export/spare")
{
    var session = Connect(url, user, password);

    // There is no "detach" call on an SR. A shared SR is joined to each host by one PBD — a physical
    // block device — and detaching the SR means unplugging every one of them. That is why an SR can
    // be attached on some hosts and not others, and why a repair action exists at all: it plugs back
    // the PBDs that are missing.
    var host = Host.get_all(session).First().opaque_ref;
    var sr = SR.create(session, host, new Dictionary<string, string>
    {
        ["server"] = nfsServer,
        ["serverpath"] = nfsPath,
        ["nfsversion"] = "3",
    }, 0, "sdk-example-lifecycle", "SR used by the SDK lifecycle example",
        "nfs", "user", true, new Dictionary<string, string>()).opaque_ref;

    var pbds = SR.get_PBDs(session, sr).Select(p => p.opaque_ref).ToList();
    Console.WriteLine($"{SR.get_name_label(session, sr)}: connected on "
                      + $"{AttachedPbds(session, pbds)} of {pbds.Count} host(s)");

    foreach (var pbd in pbds) PBD.unplug(session, pbd);
    Console.WriteLine($"  detached:   connected on {AttachedPbds(session, pbds)} host(s)");

    // Plugging them back is exactly what a repair does.
    foreach (var pbd in pbds) PBD.plug(session, pbd);
    Console.WriteLine($"  reattached: connected on {AttachedPbds(session, pbds)} host(s)");

    SR.scan(session, sr);
    Console.WriteLine($"  rescanned:  {SR.get_VDIs(session, sr).Count} disk(s)");

    // Forgetting drops the pool's record of the SR but leaves the storage itself untouched, so the
    // same export can be introduced again later. Detach before forgetting: a connected SR is in use.
    foreach (var pbd in pbds) PBD.unplug(session, pbd);
    SR.forget(session, sr);
    Console.WriteLine("  forgotten");
    Console.WriteLine("OK: manage-sr-lifecycle");
    session.logout();
}

/// <summary>How many of these connections are currently live.</summary>
private static int AttachedPbds(Session session, IEnumerable<string> pbds) =>
    pbds.Count(pbd => PBD.get_currently_attached(session, pbd));
```

<details><summary>Example output</summary>

```text
sdk-example-lifecycle: connected on 2 of 2 host(s)
  detached:   connected on 0 host(s)
  reattached: connected on 2 host(s)
  rescanned:  0 disk(s)
  forgotten
OK: manage-sr-lifecycle
```

</details>

## Go

Source: [`go/manage_sr_lifecycle.go`](../../go/manage_sr_lifecycle.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// manageSrLifecycle - Detach, reattach and forget storage.
//
// Take a storage repository offline and bring it back: disconnect it from every host, reconnect and
// rescan it, then disconnect it once more and forget it for good.
func manageSrLifecycle(url, user, password, nfsServer, nfsPath string) {
	session := connect(url, user, password)
	defer session.Logout()

	// There is no "detach" call on an SR. A shared SR is joined to each host by one PBD - a physical
	// block device - and detaching the SR means unplugging every one of them. That is why an SR can be
	// attached on some hosts and not others, and why a repair action exists at all: it plugs back the
	// PBDs that are missing.
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	sr, err := xenapi.SR.Create(session, hosts[0], map[string]string{
		"server":     nfsServer,
		"serverpath": nfsPath,
		"nfsversion": "3",
	}, 0, "sdk-example-lifecycle", "SR used by the SDK lifecycle example",
		"nfs", "user", true, map[string]string{})
	check(err)

	pbds, err := xenapi.SR.GetPBDs(session, sr)
	check(err)
	name, _ := xenapi.SR.GetNameLabel(session, sr)
	fmt.Printf("%s: connected on %d of %d host(s)\n", name, attachedPbds(session, pbds), len(pbds))

	for _, pbd := range pbds {
		check(xenapi.PBD.Unplug(session, pbd))
	}
	fmt.Printf("  detached:   connected on %d host(s)\n", attachedPbds(session, pbds))

	// Plugging them back is exactly what a repair does.
	for _, pbd := range pbds {
		check(xenapi.PBD.Plug(session, pbd))
	}
	fmt.Printf("  reattached: connected on %d host(s)\n", attachedPbds(session, pbds))

	check(xenapi.SR.Scan(session, sr))
	vdis, err := xenapi.SR.GetVDIs(session, sr)
	check(err)
	fmt.Printf("  rescanned:  %d disk(s)\n", len(vdis))

	// Forgetting drops the pool's record of the SR but leaves the storage itself untouched, so the same
	// export can be introduced again later. Detach before forgetting: a connected SR is still in use.
	for _, pbd := range pbds {
		check(xenapi.PBD.Unplug(session, pbd))
	}
	check(xenapi.SR.Forget(session, sr))
	fmt.Println("  forgotten")
	fmt.Println("OK: manage-sr-lifecycle")
}

// attachedPbds reports how many of these connections are currently live.
func attachedPbds(session *xenapi.Session, pbds []xenapi.PBDRef) int {
	live := 0
	for _, pbd := range pbds {
		attached, err := xenapi.PBD.GetCurrentlyAttached(session, pbd)
		check(err)
		if attached {
			live++
		}
	}
	return live
}
```

<details><summary>Example output</summary>

```text
sdk-example-lifecycle: connected on 2 of 2 host(s)
  detached:   connected on 0 host(s)
  reattached: connected on 2 host(s)
  rescanned:  0 disk(s)
  forgotten
OK: manage-sr-lifecycle
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/ManageSrLifecycle.java`](../../java/src/main/java/com/xenserver/samples/storage/ManageSrLifecycle.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageSrLifecycle {
    private ManageSrLifecycle() {
    }

    /**
     * Detach, reattach and forget storage.
     *
     * <p>Take a storage repository offline and bring it back: disconnect it from every host, reconnect and
     * rescan it, then disconnect it once more and forget it for good.
     */
    public static void run(String url, String user, String password,
            String nfsServer, String nfsPath) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // There is no "detach" call on an SR. A shared SR is joined to each host by one PBD - a
            // physical block device - and detaching the SR means unplugging every one of them. That is
            // why an SR can be attached on some hosts and not others, and why a repair action exists at
            // all: it plugs back the PBDs that are missing.
            Host host = Host.getAll(conn).iterator().next();
            Map<String, String> deviceConfig = new java.util.HashMap<>();
            deviceConfig.put("server", nfsServer);
            deviceConfig.put("serverpath", nfsPath);
            deviceConfig.put("nfsversion", "3");
            SR sr = SR.create(conn, host, deviceConfig, 0L,
                "sdk-example-lifecycle", "SR used by the SDK lifecycle example",
                "nfs", "user", true, new java.util.HashMap<>());

            java.util.List<PBD> pbds = new java.util.ArrayList<>(sr.getPBDs(conn));
            System.out.printf("%s: connected on %d of %d host(s)%n",
                sr.getNameLabel(conn), attachedPbds(conn, pbds), pbds.size());

            for (PBD pbd : pbds) pbd.unplug(conn);
            System.out.printf("  detached:   connected on %d host(s)%n", attachedPbds(conn, pbds));

            // Plugging them back is exactly what a repair does.
            for (PBD pbd : pbds) pbd.plug(conn);
            System.out.printf("  reattached: connected on %d host(s)%n", attachedPbds(conn, pbds));

            sr.scan(conn);
            System.out.printf("  rescanned:  %d disk(s)%n", sr.getVDIs(conn).size());

            // Forgetting drops the pool's record of the SR but leaves the storage itself untouched, so
            // the same export can be introduced again later. Detach before forgetting: a connected SR
            // is still in use.
            for (PBD pbd : pbds) pbd.unplug(conn);
            sr.forget(conn);
            System.out.println("  forgotten");
            System.out.println("OK: manage-sr-lifecycle");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * How many of these connections are currently live.
     */
    private static int attachedPbds(Connection conn, java.util.List<PBD> pbds) throws Exception {
        int live = 0;
        for (PBD pbd : pbds) if (pbd.getCurrentlyAttached(conn)) live++;
        return live;
    }
}
```

<details><summary>Example output</summary>

```text
sdk-example-lifecycle: connected on 2 of 2 host(s)
  detached:   connected on 0 host(s)
  reattached: connected on 2 host(s)
  rescanned:  0 disk(s)
  forgotten
OK: manage-sr-lifecycle
```

</details>
