<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Rolling pool update

Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time, coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the update requires, and return it to service.

**Requires:** High Availability and Workload Balancing turned off first, as the update documentation describes (turn them back on afterwards), and every running VM able to move to another host.

**Caution:** updates every host, one at a time, moving its VMs to the other hosts and restarting it if the update requires.

Workflow `rolling-pool-update`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Updates/Invoke-RollingPoolUpdate.ps1`](../../powershell/Updates/Invoke-RollingPoolUpdate.ps1)

```powershell
function Invoke-RollingPoolUpdate {
    <#
    .SYNOPSIS
        Rolling pool update.
    .DESCRIPTION
        Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
        coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if
        the update asks for that, and return it to service.
    .EXAMPLE
        Invoke-RollingPoolUpdate -Url https://xenserver -UserName root -Password $password `
            -RepoUrl https://repo.ops.xenserver.com/xs9 -SourceUrl https://repo-src.ops.xenserver.com/xs9
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    $hosts = @(Get-XenHost -Ref $pool.master) + @(Get-XenHost | Where-Object { $pool.master -ne $_ })
    # Check first that every host can be emptied: VmsWhichPreventEvacuation names the VMs that could not
    # move anywhere else (for example a VM with a disk on the host's local storage, or a pool with
    # nowhere else to put them) - stop before changing anything if there are any.
    foreach ($xenHost in $hosts) {
        $blocking = Get-XenHostProperty -XenHost $xenHost -XenProperty VmsWhichPreventEvacuation
        if ($blocking.Count -gt 0) {
            $names = ($blocking.Keys | ForEach-Object { (Get-XenVM -Ref $_).name_label }) -join ', '
            throw "$($xenHost.name_label) cannot be evacuated: move or shut down $names first"
        }
    }

    # Connect-UpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
    # update repository, which pool.sync_updates needs; it is forgotten again afterwards.
    $attached = Connect-UpdateRepository -Session $session -Pool $pool -RepoUrl $RepoUrl -SourceUrl $SourceUrl
    try {
        $hash = $pool | Invoke-XenPool -XenAction SyncUpdates -PassThru
        Write-Host "Synced updates; hash length $($hash.Length)"
        # For each host: disable it so nothing new starts there, evacuate it (live-migrating its VMs to
        # the other hosts), and let Invoke-HostUpdate apply the updates, restart the host or its
        # toolstack if the update asks for that, and enable it again. The VMs stay where evacuation put
        # them.
        foreach ($xenHost in $hosts) {
            Write-Host "Updating $($xenHost.name_label): moving its VMs to the rest of the pool"
            $xenHost | Invoke-XenHost -XenAction Disable
            Invoke-Evacuate -XenHost $xenHost
            $session = Invoke-HostUpdate -Session $session -Url $Url -UserName $UserName -Password $Password `
                -XenHost $xenHost -Hash $hash
        }
    }
    finally {
        Disconnect-UpdateRepository -Pool $pool -Attached $attached
    }
    Write-Host "OK: rolling-pool-update"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
Updating sdk-host1: moving its VMs to the rest of the pool
  applied; pending guidance = []
Updating sdk-host2: moving its VMs to the rest of the pool
  applied; pending guidance = []
OK: rolling-pool-update
```

</details>

## xe CLI

Source: [`cli/updates/rolling-pool-update.sh`](../../cli/updates/rolling-pool-update.sh)

```bash
# Rolling pool update.
#
# Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
# coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
# update asks for that, and return it to service.
#
# Run it:
#   ./workflows.sh rolling-pool-update https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)

# Check first that every host can be emptied: host-get-vms-which-prevent-evacuation names the VMs that
# could not move anywhere else (for example a VM with a disk on the host's local storage, or a pool with
# nowhere else to put them) - stop before changing anything if there are any. Then, for each host:
# disable it so nothing new starts there, evacuate it (live-migrating its VMs to the other hosts), and
# let helpers.sh's apply_updates_to_host apply the updates, reboot the host if the update asks for that
# (xe has no remote toolstack-restart command, see helpers.sh), and enable it again. The VMs stay where
# evacuation put them. attach_update_repository checks that HA and Workload Balancing are off and
# attaches a throwaway update repository, which pool-sync-updates needs; it is forgotten again
# afterwards.
rolling_pool_update() {
    local master h hosts blocking vm names hash
    master=$(remote_xe pool-param-get uuid="$(remote_xe pool-list --minimal)" param-name=master)
    hosts=$master
    for h in $(each_csv "$(remote_xe host-list --minimal)"); do
        [ "$h" = "$master" ] || hosts="$hosts $h"
    done
    for h in $hosts; do
        blocking=$(remote_xe host-get-vms-which-prevent-evacuation uuid=$h --minimal)
        if [ -n "$blocking" ]; then
            names=""
            for vm in $(each_csv "$blocking"); do
                names="${names:+$names, }$(remote_xe vm-param-get uuid=$vm param-name=name-label)"
            done
            echo "$(remote_xe host-param-get uuid=$h param-name=name-label) cannot be evacuated:" \
                 "move or shut down $names first" >&2
            exit 1
        fi
    done
    attach_update_repository "$(param repo_url "https://repo.ops.xenserver.com/xs9")" \
        "$(param source_url "https://repo-src.ops.xenserver.com/xs9")"

    hash=$(remote_xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    for h in $hosts; do
        echo "Updating $(remote_xe host-param-get uuid=$h param-name=name-label): moving its VMs to the rest of the pool"
        remote_xe host-disable uuid=$h
        remote_xe host-evacuate uuid=$h
        apply_updates_to_host "$h" "$hash"
    done
    ok rolling-pool-update
}
```

<details><summary>Example output</summary>

```text
Synced updates (hash length 64)
Updating sdk-host1: moving its VMs to the rest of the pool
  applied; pending guidance = []
Updating sdk-host2: moving its VMs to the rest of the pool
  applied; pending guidance = []
OK: rolling-pool-update
```

</details>

## Python

Source: [`python/updates/rolling_pool_update.py`](../../python/updates/rolling_pool_update.py)

```python
"""Rolling pool update.

Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
update asks for that, and return it to service.

Run it::

    rolling_pool_update("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

from connection import connect
from helpers import apply_updates_to_host, attach_update_repository, detach_update_repository


def rolling_pool_update(url, username, password, repo_url, source_url):
    """Update the whole pool host by host, coordinator first, moving each host's VMs off it before
    updating it, so the VMs keep running throughout.

    Check first that every host can be emptied: host.get_vms_which_prevent_evacuation names the VMs
    that could not move anywhere else (for example a VM with a disk on the host's local storage, or
    a pool with nowhere else to put them) - stop before changing anything if there are any. Then,
    for each host: disable it so nothing new starts there, evacuate it (live-migrating its VMs to
    the other hosts), and let helpers.apply_updates_to_host apply the updates, restart the host or
    its toolstack if the update asks for that, and enable it again. The VMs stay where evacuation
    put them. helpers.attach_update_repository checks that HA and Workload Balancing are off and
    attaches a throwaway update repository, which pool.sync_updates needs; it is forgotten again
    afterwards."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    master = session.xenapi.pool.get_master(pool)
    hosts = [master] + [ref for ref in session.xenapi.host.get_all() if ref != master]
    for host_ref in hosts:
        blocking = session.xenapi.host.get_vms_which_prevent_evacuation(host_ref)
        if blocking:
            names = ", ".join(session.xenapi.VM.get_name_label(vm) for vm in blocking)
            raise RuntimeError("%s cannot be evacuated: move or shut down %s first"
                               % (session.xenapi.host.get_name_label(host_ref), names))

    repo, previous = attach_update_repository(session, pool, repo_url, source_url)
    try:
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))
        for host_ref in hosts:
            print("Updating %s: moving its VMs to the rest of the pool"
                  % session.xenapi.host.get_name_label(host_ref))
            session.xenapi.host.disable(host_ref)
            session.xenapi.host.evacuate(host_ref)
            session = apply_updates_to_host(session, url, username, password, host_ref, hash_)
    finally:
        detach_update_repository(session, pool, repo, previous)
    print("OK: rolling-pool-update")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
Updating sdk-host1: moving its VMs to the rest of the pool
  applied; pending guidance = []
Updating sdk-host2: moving its VMs to the rest of the pool
  applied; pending guidance = []
OK: rolling-pool-update
```

</details>

## C# (.NET)

Source: [`csharp/Updates/RollingPoolUpdate.cs`](../../csharp/Updates/RollingPoolUpdate.cs)

```csharp
/// <summary>
/// Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
/// coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
/// update asks for that, and return it to service.
/// </summary>
/// <example>
/// <code>
/// Workflows.RollingPoolUpdate("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
///     "https://repo-src.ops.xenserver.com/xs9");
/// </code>
/// </example>
public static void RollingPoolUpdate(string url, string user, string password, string repoUrl, string sourceUrl)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0];
    var master = Pool.get_master(session, pool);
    var hosts = new[] { master }.Concat(Host.get_all(session).Where(r => !r.Equals(master))).ToList();
    // Check first that every host can be emptied: get_vms_which_prevent_evacuation names the VMs that
    // could not move anywhere else (for example a VM with a disk on the host's local storage, or a pool
    // with nowhere else to put them) - stop before changing anything if there are any.
    foreach (var hostRef in hosts)
    {
        var blocking = Host.get_vms_which_prevent_evacuation(session, hostRef);
        if (blocking.Count > 0)
            throw new InvalidOperationException(
                $"{Host.get_name_label(session, hostRef)} cannot be evacuated: move or shut down " +
                $"{string.Join(", ", blocking.Keys.Select(vm => VM.get_name_label(session, vm)))} first");
    }

    // AttachUpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
    // update repository, which Pool.sync_updates needs; it is forgotten again afterwards.
    var (repo, previous) = AttachUpdateRepository(session, pool, repoUrl, sourceUrl);
    try
    {
        var hash = Pool.sync_updates(session, pool, false, "", "");
        Console.WriteLine($"Synced updates; hash length {hash.Length}");
        // For each host: disable it so nothing new starts there, evacuate it (live-migrating its VMs
        // to the other hosts), and let ApplyUpdatesToHost apply the updates, restart the host or its
        // toolstack if the update asks for that, and enable it again. The VMs stay where evacuation
        // put them.
        foreach (var hostRef in hosts)
        {
            Console.WriteLine($"Updating {Host.get_name_label(session, hostRef)}: moving its VMs to the rest of the pool");
            Host.disable(session, hostRef);
            Host.evacuate(session, hostRef);
            session = ApplyUpdatesToHost(session, url, user, password, hostRef, hash);
        }
    }
    finally
    {
        DetachUpdateRepository(session, pool, repo, previous);
    }
    Console.WriteLine("OK: rolling-pool-update");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
Updating sdk-host1: moving its VMs to the rest of the pool
  applied; pending guidance = []
Updating sdk-host2: moving its VMs to the rest of the pool
  applied; pending guidance = []
OK: rolling-pool-update
```

</details>

## Go

Source: [`go/rolling_pool_update.go`](../../go/rolling_pool_update.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// rollingPoolUpdate - Rolling pool update.
//
// Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
// coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
// update asks for that, and return it to service.
//
// Check first that every host can be emptied: Host.GetVmsWhichPreventEvacuation names the VMs that
// could not move anywhere else (for example a VM with a disk on the host's local storage, or a pool
// with nowhere else to put them) - stop before changing anything if there are any. Then, for each
// host: disable it so nothing new starts there, evacuate it (live-migrating its VMs to the other
// hosts), and let applyUpdatesToHost apply the updates, restart the host or its toolstack if the
// update asks for that, and enable it again. The VMs stay where evacuation put them.
// attachUpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway update
// repository, which Pool.SyncUpdates needs; it is forgotten again afterwards.
func rollingPoolUpdate(url, user, password, repoURL, sourceURL string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	master, err := xenapi.Pool.GetMaster(session, pool)
	check(err)
	all, err := xenapi.Host.GetAll(session)
	check(err)
	hosts := []xenapi.HostRef{master}
	for _, hostRef := range all {
		if hostRef != master {
			hosts = append(hosts, hostRef)
		}
	}
	for _, hostRef := range hosts {
		blocking, err := xenapi.Host.GetVmsWhichPreventEvacuation(session, hostRef)
		check(err)
		if len(blocking) > 0 {
			var names []string
			for vm := range blocking {
				name, err := xenapi.VM.GetNameLabel(session, vm)
				check(err)
				names = append(names, name)
			}
			hostName, err := xenapi.Host.GetNameLabel(session, hostRef)
			check(err)
			panic(fmt.Sprintf("%s cannot be evacuated: move or shut down %s first", hostName,
				strings.Join(names, ", ")))
		}
	}

	repo, previous := attachUpdateRepository(session, pool, repoURL, sourceURL)
	defer func() { detachUpdateRepository(session, pool, repo, previous) }()
	hash, err := xenapi.Pool.SyncUpdates5(session, pool, false, "", "")
	check(err)
	fmt.Printf("Synced updates; hash length %d\n", len(hash))
	for _, hostRef := range hosts {
		name, err := xenapi.Host.GetNameLabel(session, hostRef)
		check(err)
		fmt.Printf("Updating %s: moving its VMs to the rest of the pool\n", name)
		check(xenapi.Host.Disable(session, hostRef, true))
		check(xenapi.Host.Evacuate2(session, hostRef))
		session = applyUpdatesToHost(session, url, user, password, hostRef, hash, "")
	}
	fmt.Println("OK: rolling-pool-update")
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
Updating sdk-host1: moving its VMs to the rest of the pool
  applied; pending guidance = []
Updating sdk-host2: moving its VMs to the rest of the pool
  applied; pending guidance = []
OK: rolling-pool-update
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/updates/RollingPoolUpdate.java`](../../java/src/main/java/com/xenserver/samples/updates/RollingPoolUpdate.java)

```java
package com.xenserver.samples.updates;

import com.xenserver.samples.Helpers.AttachedRepository;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.applyUpdatesToHost;
import static com.xenserver.samples.Helpers.attachUpdateRepository;
import static com.xenserver.samples.Helpers.detachUpdateRepository;
import static com.xenserver.samples.PoolConnection.connect;

public final class RollingPoolUpdate {
    private RollingPoolUpdate() {
    }

    /**
     * Rolling pool update.
     *
     * <p>Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
     * coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
     * update asks for that, and return it to service.
     *
     * <p>Check first that every host can be emptied: host.getVmsWhichPreventEvacuation names the VMs that
     * could not move anywhere else (for example a VM with a disk on the host's local storage, or a pool with
     * nowhere else to put them) - stop before changing anything if there are any. Then, for each host:
     * disable it so nothing new starts there, evacuate it (live-migrating its VMs to the other hosts), and
     * let Helpers.applyUpdatesToHost apply the updates, restart the host or its toolstack if the update asks
     * for that, and enable it again. The VMs stay where evacuation put them.
     * Helpers.attachUpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
     * update repository, which pool.syncUpdates needs; it is forgotten again afterwards.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * RollingPoolUpdate.run("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
     * "https://repo-src.ops.xenserver.com/xs9");
     * }</pre>
     */
    public static void run(String url, String user, String password, String repoUrl,
            String sourceUrl) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        Host master = pool.getMaster(conn);
        List<Host> hosts = new ArrayList<>();
        hosts.add(master);
        for (Host h : Host.getAll(conn)) {
            if (!h.equals(master)) hosts.add(h);
        }
        for (Host host : hosts) {
            Map<VM, Set<String>> blocking = host.getVmsWhichPreventEvacuation(conn);
            if (!blocking.isEmpty()) {
                List<String> names = new ArrayList<>();
                for (VM vm : blocking.keySet()) names.add(vm.getNameLabel(conn));
                throw new IllegalStateException(host.getNameLabel(conn) + " cannot be evacuated: move or shut down "
                        + String.join(", ", names) + " first");
            }
        }

        AttachedRepository attached = attachUpdateRepository(conn, pool, repoUrl, sourceUrl);
        try {
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());
            for (Host host : hosts) {
                System.out.println("Updating " + host.getNameLabel(conn) + ": moving its VMs to the rest of the pool");
                host.disable(conn);
                host.evacuate(conn);
                conn = applyUpdatesToHost(conn, url, user, password, host, hash, "");
            }
        } finally {
            detachUpdateRepository(conn, pool, attached);
        }
        System.out.println("OK: rolling-pool-update");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
Updating sdk-host1: moving its VMs to the rest of the pool
  applied; pending guidance = []
Updating sdk-host2: moving its VMs to the rest of the pool
  applied; pending guidance = []
OK: rolling-pool-update
```

</details>
