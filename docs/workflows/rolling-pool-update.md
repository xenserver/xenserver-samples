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
    $hosts = Get-HostsCoordinatorFirst
    # Check first, before changing anything, that the update can go through: no host or VM may still have
    # mandatory guidance pending from an earlier update, and every host must be able to empty.
    Assert-NoPendingGuidance
    Assert-HostsCanBeEvacuated -Hosts $hosts

    # Connect-UpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
    # update repository, which pool.sync_updates needs; it is forgotten again afterwards.
    $attached = Connect-UpdateRepository -Session $session -Pool $pool -RepoUrl $RepoUrl -SourceUrl $SourceUrl
    try {
        $hash = $pool | Invoke-XenPool -XenAction SyncUpdates -PassThru
        Write-Host "Synced updates; hash length $($hash.Length)"
        # Update-Hosts updates each host in turn: disable it, evacuate it, apply the updates, restart it or
        # its toolstack if the update asks for that, and enable it again.
        $session = Update-Hosts -Session $session -Url $Url -UserName $UserName -Password $Password `
            -Hosts $hosts -Hash $hash
    }
    finally {
        Disconnect-UpdateRepository -Pool $pool -Attached $attached
    }
    # Restarting a VM to pick the update up is its owner's call: report what is left.
    Write-VmGuidance
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
VM guidance pending: none
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

# Check first, before changing anything, that the update can go through: no host or VM may still have
# mandatory guidance pending from an earlier update, and every host must be able to empty
# (check_no_pending_guidance, check_hosts_can_be_evacuated). Then sync, and let update_hosts update each
# host in turn: disable it, evacuate it, apply the updates, reboot it if the update asks for that (xe has
# no remote toolstack-restart command, see helpers.sh), and enable it again. Finally report the guidance
# left for VMs, such as restarting one to pick the update up - that is the VM owner's call.
# attach_update_repository checks that HA and Workload Balancing are off and attaches a throwaway update
# repository, which pool-sync-updates needs; it is forgotten again afterwards.
rolling_pool_update() {
    local hosts hash
    hosts=$(hosts_coordinator_first)
    check_no_pending_guidance
    check_hosts_can_be_evacuated $hosts
    attach_update_repository "$(param repo_url "https://repo.ops.xenserver.com/xs9")" \
        "$(param source_url "https://repo-src.ops.xenserver.com/xs9")"

    hash=$(remote_xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    update_hosts "$hash" $hosts
    report_vm_guidance
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
VM guidance pending: none
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
from helpers import (attach_update_repository, check_hosts_can_be_evacuated, check_no_pending_guidance,
                     detach_update_repository, hosts_coordinator_first, report_vm_guidance, update_hosts)


def rolling_pool_update(url, username, password, repo_url, source_url):
    """Update the whole pool host by host, coordinator first, moving each host's VMs off it before
    updating it, so the VMs keep running throughout.

    Check first, before changing anything, that the update can go through: no host or VM may still
    have mandatory guidance pending from an earlier update, and every host must be able to empty
    (helpers.check_no_pending_guidance, helpers.check_hosts_can_be_evacuated). Then sync, and let
    helpers.update_hosts update each host in turn: disable it, evacuate it, apply the updates,
    restart it or its toolstack if the update asks for that, and enable it again. Finally report the
    guidance left for VMs, such as restarting one to pick the update up - that is the VM owner's
    call. helpers.attach_update_repository checks that HA and Workload Balancing are off and
    attaches a throwaway update repository, which pool.sync_updates needs; it is forgotten again
    afterwards."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    hosts = hosts_coordinator_first(session)
    check_no_pending_guidance(session)
    check_hosts_can_be_evacuated(session, hosts)

    repo, previous = attach_update_repository(session, pool, repo_url, source_url)
    try:
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))
        session = update_hosts(session, url, username, password, hosts, hash_)
    finally:
        detach_update_repository(session, pool, repo, previous)
    report_vm_guidance(session)
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
VM guidance pending: none
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
    var hosts = HostsCoordinatorFirst(session);
    // Check first, before changing anything, that the update can go through: no host or VM may still have
    // mandatory guidance pending from an earlier update, and every host must be able to empty.
    CheckNoPendingGuidance(session);
    CheckHostsCanBeEvacuated(session, hosts);

    // AttachUpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
    // update repository, which Pool.sync_updates needs; it is forgotten again afterwards.
    var (repo, previous) = AttachUpdateRepository(session, pool, repoUrl, sourceUrl);
    try
    {
        var hash = Pool.sync_updates(session, pool, false, "", "");
        Console.WriteLine($"Synced updates; hash length {hash.Length}");
        // UpdateHosts updates each host in turn: disable it, evacuate it, apply the updates, restart it or
        // its toolstack if the update asks for that, and enable it again.
        session = UpdateHosts(session, url, user, password, hosts, hash);
    }
    finally
    {
        DetachUpdateRepository(session, pool, repo, previous);
    }
    // Restarting a VM to pick the update up is its owner's call: report what is left.
    ReportVmGuidance(session);
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
VM guidance pending: none
OK: rolling-pool-update
```

</details>

## Go

Source: [`go/rolling_pool_update.go`](../../go/rolling_pool_update.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// rollingPoolUpdate - Rolling pool update.
//
// Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
// coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
// update asks for that, and return it to service.
//
// Check first, before changing anything, that the update can go through: no host or VM may still
// have mandatory guidance pending from an earlier update, and every host must be able to empty
// (checkNoPendingGuidance, checkHostsCanBeEvacuated). Then sync, and let updateHosts update each host
// in turn: disable it, evacuate it, apply the updates, restart it or its toolstack if the update asks
// for that, and enable it again. Finally report the guidance left for VMs, such as restarting one to
// pick the update up - that is the VM owner's call. attachUpdateRepository checks that HA and
// Workload Balancing are off and attaches a throwaway update repository, which Pool.SyncUpdates
// needs; it is forgotten again afterwards.
func rollingPoolUpdate(url, user, password, repoURL, sourceURL string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	hosts := hostsCoordinatorFirst(session)
	checkNoPendingGuidance(session)
	checkHostsCanBeEvacuated(session, hosts)

	repo, previous := attachUpdateRepository(session, pool, repoURL, sourceURL)
	defer func() { detachUpdateRepository(session, pool, repo, previous) }()
	hash, err := xenapi.Pool.SyncUpdates5(session, pool, false, "", "")
	check(err)
	fmt.Printf("Synced updates; hash length %d\n", len(hash))
	session = updateHosts(session, url, user, password, hosts, hash)
	reportVMGuidance(session)
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
VM guidance pending: none
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

import java.util.List;

import static com.xenserver.samples.Helpers.attachUpdateRepository;
import static com.xenserver.samples.Helpers.checkHostsCanBeEvacuated;
import static com.xenserver.samples.Helpers.checkNoPendingGuidance;
import static com.xenserver.samples.Helpers.detachUpdateRepository;
import static com.xenserver.samples.Helpers.hostsCoordinatorFirst;
import static com.xenserver.samples.Helpers.reportVmGuidance;
import static com.xenserver.samples.Helpers.updateHosts;
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
     * <p>Check first, before changing anything, that the update can go through: no host or VM may still have
     * mandatory guidance pending from an earlier update, and every host must be able to empty
     * (Helpers.checkNoPendingGuidance, Helpers.checkHostsCanBeEvacuated). Then sync, and let
     * Helpers.updateHosts update each host in turn: disable it, evacuate it, apply the updates, restart it or
     * its toolstack if the update asks for that, and enable it again. Finally report the guidance left for
     * VMs, such as restarting one to pick the update up - that is the VM owner's call.
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
        List<Host> hosts = hostsCoordinatorFirst(conn);
        checkNoPendingGuidance(conn);
        checkHostsCanBeEvacuated(conn, hosts);

        AttachedRepository attached = attachUpdateRepository(conn, pool, repoUrl, sourceUrl);
        try {
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());
            conn = updateHosts(conn, url, user, password, hosts, hash);
        } finally {
            detachUpdateRepository(conn, pool, attached);
        }
        reportVmGuidance(conn);
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
VM guidance pending: none
OK: rolling-pool-update
```

</details>
