<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Apply updates from the CDN

Sync the pool's update metadata from the CDN and apply it to one host - the coordinator, unless you name another with host_name - then act on that host's post-update guidance.

**Requires:** High Availability and Workload Balancing turned off first, as the update documentation describes (turn them back on afterwards).

**Caution:** updates the host, restarting it if the update requires.

Workflow `apply-update`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Updates/Invoke-ApplyUpdate.ps1`](../../powershell/Updates/Invoke-ApplyUpdate.ps1)

```powershell
function Invoke-ApplyUpdate {
    <#
    .SYNOPSIS
        Apply updates from the CDN.
    .DESCRIPTION
        Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator,
        unless you name another - then act on that host's post-update guidance.
    .EXAMPLE
        Invoke-ApplyUpdate -Url https://xenserver -UserName root -Password $password `
            -RepoUrl https://repo.ops.xenserver.com/xs9 -SourceUrl https://repo-src.ops.xenserver.com/xs9
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$SourceUrl,
        [string]$HostName = ""
    )
    # The documentation asks for the coordinator to be updated before any other host, so update it
    # first, then run this again naming each of the others - or use Invoke-RollingPoolUpdate to do the
    # whole pool in one go. Connect-UpdateRepository checks that HA and Workload Balancing are off and
    # attaches a throwaway update repository, which pool.sync_updates needs; it is forgotten again
    # afterwards. Invoke-HostUpdate does the rest: evacuating the host first if that turns out to be
    # needed, acting on its post-update guidance, and returning it to service.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    if ($HostName) {
        $hosts = @(Get-XenHost -Name $HostName)
        if ($hosts.Count -ne 1) {
            throw "expected one host named '$HostName', found $($hosts.Count)"
        }
        $xenHost = $hosts[0]
    }
    else {
        $xenHost = Get-XenHost -Ref $pool.master
    }

    $attached = Connect-UpdateRepository -Session $session -Pool $pool -RepoUrl $RepoUrl -SourceUrl $SourceUrl
    try {
        # Sync the pool's update metadata; -PassThru returns the hash identifying the synced set.
        $hash = $pool | Invoke-XenPool -XenAction SyncUpdates -PassThru
        Write-Host "Synced updates; hash length $($hash.Length)"
        $session = Invoke-HostUpdate -Session $session -Url $Url -UserName $UserName -Password $Password `
            -XenHost $xenHost -Hash $hash -Label "$($xenHost.name_label): "
    }
    finally {
        Disconnect-UpdateRepository -Pool $pool -Attached $attached
    }
    Write-Host "OK: apply-update"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
  sdk-host1: applied; pending guidance = []
OK: apply-update
```

</details>

## xe CLI

Source: [`cli/updates/apply-update.sh`](../../cli/updates/apply-update.sh)

```bash
# Apply updates from the CDN.
#
# Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator, unless
# you name another - then act on that host's post-update guidance.
#
# Run it:
#   ./workflows.sh apply-update https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)
#   host_name (empty: the coordinator)

# The documentation asks for the coordinator to be updated before any other host, so update it first,
# then run this again naming each of the others - or use rolling-pool-update to do the whole pool in one
# go. helpers.sh's attach_update_repository checks that HA and Workload Balancing are off and attaches a
# throwaway update repository, which pool-sync-updates needs; it is forgotten again afterwards.
# apply_updates_to_host does the rest: evacuating the host first if that turns out to be needed, acting
# on its post-update guidance, and returning it to service.
apply_update() {
    local host_name h hash
    host_name=$(param host_name "")
    if [ -n "$host_name" ]; then
        h=$(remote_xe host-list name-label="$host_name" --minimal)
        if [ -z "$h" ] || [ "$h" != "${h%%,*}" ]; then
            echo "expected one host named '$host_name', found $(each_csv "$h" | wc -w)" >&2
            exit 1
        fi
    else
        h=$(remote_xe pool-param-get uuid="$(remote_xe pool-list --minimal)" param-name=master)
    fi
    attach_update_repository "$(param repo_url "https://repo.ops.xenserver.com/xs9")" \
        "$(param source_url "https://repo-src.ops.xenserver.com/xs9")"

    hash=$(remote_xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    apply_updates_to_host "$h" "$hash" "$(remote_xe host-param-get uuid=$h param-name=name-label): "
    ok apply-update
}
```

<details><summary>Example output</summary>

```text
Synced updates (hash length 64)
  sdk-host1: applied; pending guidance = []
OK: apply-update
```

</details>

## Python

Source: [`python/updates/apply_update.py`](../../python/updates/apply_update.py)

```python
"""Apply updates from the CDN.

Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator, unless
you name another - then act on that host's post-update guidance.

Run it::

    apply_update("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

from connection import connect
from helpers import apply_updates_to_host, attach_update_repository, detach_update_repository


def apply_update(url, username, password, repo_url, source_url, host_name=""):
    """Sync the pool's update metadata from the CDN, then apply the synced updates to one host: the
    one named `host_name`, or the coordinator if no name is given.

    The documentation asks for the coordinator to be updated before any other host, so update it
    first, then run this again naming each of the others - or use rolling-pool-update to do the
    whole pool in one go. helpers.attach_update_repository checks that HA and Workload Balancing are
    off and attaches a throwaway update repository, which pool.sync_updates needs; it is forgotten
    again afterwards. helpers.apply_updates_to_host does the rest: evacuating the host first if that
    turns out to be needed, acting on its post-update guidance, and returning it to service."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    if host_name:
        hosts = session.xenapi.host.get_by_name_label(host_name)
        if len(hosts) != 1:
            raise RuntimeError("expected one host named %r, found %d" % (host_name, len(hosts)))
        host_ref = hosts[0]
    else:
        host_ref = session.xenapi.pool.get_master(pool)
    name = session.xenapi.host.get_name_label(host_ref)

    repo, previous = attach_update_repository(session, pool, repo_url, source_url)
    try:
        # Sync the pool's update metadata; the returned hash identifies the synced set.
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))
        session = apply_updates_to_host(session, url, username, password, host_ref, hash_,
                                        label="%s: " % name)
    finally:
        detach_update_repository(session, pool, repo, previous)
    print("OK: apply-update")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
  sdk-host1: applied; pending guidance = []
OK: apply-update
```

</details>

## C# (.NET)

Source: [`csharp/Updates/ApplyUpdate.cs`](../../csharp/Updates/ApplyUpdate.cs)

```csharp
/// <summary>
/// Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator, unless
/// you name another - then act on that host's post-update guidance.
/// </summary>
/// <example>
/// <code>
/// Workflows.ApplyUpdate("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
///     "https://repo-src.ops.xenserver.com/xs9");
/// </code>
/// </example>
public static void ApplyUpdate(string url, string user, string password, string repoUrl, string sourceUrl,
    string hostName = "")
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0];
    // The documentation asks for the coordinator to be updated before any other host, so update it
    // first, then run this again naming each of the others - or use rolling-pool-update to do the
    // whole pool in one go.
    XenRef<Host> hostRef;
    if (hostName != "")
    {
        var hosts = Host.get_by_name_label(session, hostName);
        if (hosts.Count != 1)
            throw new InvalidOperationException($"expected one host named '{hostName}', found {hosts.Count}");
        hostRef = hosts[0];
    }
    else
    {
        hostRef = Pool.get_master(session, pool);
    }
    var name = Host.get_name_label(session, hostRef);

    // AttachUpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway
    // update repository, which Pool.sync_updates needs; it is forgotten again afterwards.
    var (repo, previous) = AttachUpdateRepository(session, pool, repoUrl, sourceUrl);
    try
    {
        // Sync the pool's update metadata; the returned hash identifies the synced set.
        var hash = Pool.sync_updates(session, pool, false, "", "");
        Console.WriteLine($"Synced updates; hash length {hash.Length}");
        // ApplyUpdatesToHost does the rest: evacuating the host first if that turns out to be needed,
        // acting on its post-update guidance, and returning it to service.
        session = ApplyUpdatesToHost(session, url, user, password, hostRef, hash, $"{name}: ");
    }
    finally
    {
        DetachUpdateRepository(session, pool, repo, previous);
    }
    Console.WriteLine("OK: apply-update");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
  sdk-host1: applied; pending guidance = []
OK: apply-update
```

</details>

## Go

Source: [`go/apply_update.go`](../../go/apply_update.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// applyUpdate - Apply updates from the CDN.
//
// Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator, unless
// you name another - then act on that host's post-update guidance.
//
// The documentation asks for the coordinator to be updated before any other host, so update it first,
// then run this again naming each of the others - or use rolling-pool-update to do the whole pool in
// one go. attachUpdateRepository checks that HA and Workload Balancing are off and attaches a
// throwaway update repository, which Pool.SyncUpdates needs; it is forgotten again afterwards.
// applyUpdatesToHost does the rest: evacuating the host first if that turns out to be needed, acting
// on its post-update guidance, and returning it to service.
func applyUpdate(url, user, password, repoURL, sourceURL, hostName string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	var hostRef xenapi.HostRef
	if hostName != "" {
		hosts, err := xenapi.Host.GetByNameLabel(session, hostName)
		check(err)
		if len(hosts) != 1 {
			panic(fmt.Sprintf("expected one host named %q, found %d", hostName, len(hosts)))
		}
		hostRef = hosts[0]
	} else {
		hostRef, err = xenapi.Pool.GetMaster(session, pool)
		check(err)
	}
	name, err := xenapi.Host.GetNameLabel(session, hostRef)
	check(err)

	repo, previous := attachUpdateRepository(session, pool, repoURL, sourceURL)
	defer func() { detachUpdateRepository(session, pool, repo, previous) }()
	// Sync the pool's update metadata; the returned hash identifies the synced set.
	hash, err := xenapi.Pool.SyncUpdates5(session, pool, false, "", "")
	check(err)
	fmt.Printf("Synced updates; hash length %d\n", len(hash))
	session = applyUpdatesToHost(session, url, user, password, hostRef, hash, name+": ")
	fmt.Println("OK: apply-update")
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
  sdk-host1: applied; pending guidance = []
OK: apply-update
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/updates/ApplyUpdate.java`](../../java/src/main/java/com/xenserver/samples/updates/ApplyUpdate.java)

```java
package com.xenserver.samples.updates;

import com.xenserver.samples.Helpers.AttachedRepository;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import java.util.Set;

import static com.xenserver.samples.Helpers.applyUpdatesToHost;
import static com.xenserver.samples.Helpers.attachUpdateRepository;
import static com.xenserver.samples.Helpers.detachUpdateRepository;
import static com.xenserver.samples.PoolConnection.connect;

public final class ApplyUpdate {
    private ApplyUpdate() {
    }

    /**
     * Apply updates from the CDN.
     *
     * <p>Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator,
     * unless you name another - then act on that host's post-update guidance.
     *
     * <p>The documentation asks for the coordinator to be updated before any other host, so update it
     * first, then run this again naming each of the others - or use RollingPoolUpdate to do the whole pool
     * in one go. Helpers.attachUpdateRepository checks that HA and Workload Balancing are off and attaches
     * a throwaway update repository, which pool.syncUpdates needs; it is forgotten again afterwards.
     * Helpers.applyUpdatesToHost does the rest: evacuating the host first if that turns out to be needed,
     * acting on its post-update guidance, and returning it to service.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ApplyUpdate.run("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
     * "https://repo-src.ops.xenserver.com/xs9", "");
     * }</pre>
     */
    public static void run(String url, String user, String password, String repoUrl,
            String sourceUrl, String hostName) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        Host host;
        if (!hostName.isEmpty()) {
            Set<Host> hosts = Host.getByNameLabel(conn, hostName);
            if (hosts.size() != 1) {
                throw new IllegalStateException("expected one host named '" + hostName + "', found "
                        + hosts.size());
            }
            host = hosts.iterator().next();
        } else {
            host = pool.getMaster(conn);
        }
        String name = host.getNameLabel(conn);

        AttachedRepository attached = attachUpdateRepository(conn, pool, repoUrl, sourceUrl);
        try {
            // Sync the pool's update metadata; the returned hash identifies the synced set.
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());
            conn = applyUpdatesToHost(conn, url, user, password, host, hash, name + ": ");
        } finally {
            detachUpdateRepository(conn, pool, attached);
        }
        System.out.println("OK: apply-update");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
  sdk-host1: applied; pending guidance = []
OK: apply-update
```

</details>
