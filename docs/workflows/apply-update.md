<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Apply updates from the CDN

Sync the pool's update metadata from the CDN and apply it to every host, then read each host's post-update reboot guidance.

**Requires:** High Availability and Workload Balancing turned off first, as the update documentation describes (turn them back on afterwards).

**Caution:** updates the hosts.

Workflow `apply-update`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Updates/ApplyUpdate.cs`](../../csharp/Updates/ApplyUpdate.cs)

```csharp
/// <summary>
/// Sync the pool's update metadata from the CDN and apply it to every host, starting with the pool
/// coordinator, then read each host's post-update reboot guidance.
/// </summary>
/// <example>
/// <code>
/// Workflows.ApplyUpdate("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
/// Workflows."https://repo-src.ops.xenserver.com/xs9");
/// </code>
/// </example>
public static void ApplyUpdate(string url, string user, string password, string repoUrl, string sourceUrl)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0].opaque_ref;
    // Host.apply_updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks
    // for Workload Balancing to be switched off before you start updating - so check both up front
    // and stop rather than disabling either for you; turn them back on again once the update is done.
    if (Pool.get_ha_enabled(session, pool) || Pool.get_wlb_enabled(session, pool))
        throw new Exception("HA and Workload Balancing must both be off before updating the pool; " +
                             "disable them, run this again, then re-enable them once it finishes");
    // pool.sync_updates needs at least one repository with update=true enabled
    // (NO_REPOSITORY_ENABLED otherwise) - introduce and attach a throwaway one, and forget it again
    // afterwards.
    var repos = IntroduceUpdateRepositories(session, repoUrl, sourceUrl);
    // Remember the pool's own repositories, to put them back afterwards.
    var previous = Pool.get_repositories(session, pool);
    Pool.set_repositories(session, pool, repos);
    try
    {
        // Sync the pool's update metadata; the returned hash identifies the synced set.
        var hash = Pool.sync_updates(session, pool, false, "", "");
        Console.WriteLine($"Synced updates; hash length {hash.Length}");

        // Apply the synced updates to each host, coordinator first as the documentation requires.
        // Then read the reboot guidance to decide whether a host needs a reboot. Applying a batch
        // whose mandatory guidance needs an evacuation fails with HOST_EVACUATION_IS_REQUIRED
        // unless the host's resident VMs are moved off first - handle that rather than assuming
        // an update batch never needs one. (Guidance that targets VMs instead of hosts, for
        // example restarting a VM, is not handled here.)
        var hosts = Host.get_all_records(session);
        var master = Pool.get_master(session, pool);
        var orderedRefs = new[] { master }.Concat(hosts.Keys.Where(r => r.opaque_ref != master.opaque_ref));
        foreach (var hostRef in orderedRefs)
        {
            var host = hosts[hostRef];
            try
            {
                Host.apply_updates(session, hostRef.opaque_ref, hash);
            }
            catch (Failure f) when (f.ErrorDescription[0] == "HOST_EVACUATION_IS_REQUIRED")
            {
                Console.WriteLine($"  {host.name_label}: needs evacuating first; evacuating and retrying");
                Host.disable(session, hostRef.opaque_ref);
                Host.evacuate(session, hostRef.opaque_ref);
                Host.apply_updates(session, hostRef.opaque_ref, hash);
                Host.enable(session, hostRef.opaque_ref);
            }
            var guidance = Host.get_pending_guidances(session, hostRef.opaque_ref);
            Console.WriteLine($"  {host.name_label}: applied; pending guidance = " +
                              $"[{string.Join(", ", guidance)}]");
            // Modern xapi (>=23.18.0) doesn't reboot a host for you: it only records pending_guidances,
            // so only reboot (or restart the toolstack) when the applied batch actually asks for it.
            if (guidance.Contains(update_guidances.reboot_host) ||
                guidance.Contains(update_guidances.restart_toolstack))
            {
                // As in rolling-pool-update: either restart returns before it has happened, and the
                // coordinator's takes this session with it - so wait for it, reconnecting.
                var rebooting = guidance.Contains(update_guidances.reboot_host);
                var key = rebooting ? "boot_time" : "agent_start_time";
                Host.get_other_config(session, hostRef.opaque_ref).TryGetValue(key, out var before);
                if (rebooting) Host.reboot(session, hostRef.opaque_ref);
                else Host.restart_agent(session, hostRef.opaque_ref);
                session = WaitForRestart(url, user, password, host.uuid, key, before);
            }
            // apply_updates disables the host while it works (auto_enable: a restart puts it back) -
            // with no restart to do, nothing re-enables it. Return it to service either way.
            EnableWhenBooted(session, hostRef.opaque_ref);
        }
    }
    finally
    {
        Pool.set_repositories(session, pool, previous);
        foreach (var repo in repos) Repository.forget(session, repo.opaque_ref);
    }
    Console.WriteLine("OK: apply-update");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
  sdk-host1: applied; pending guidance = []
  sdk-host2: applied; pending guidance = []
OK: apply-update
```

</details>

## Python

Source: [`python/updates/apply_update.py`](../../python/updates/apply_update.py)

```python
"""Apply updates from the CDN.

Sync the pool's update metadata from the CDN and apply it to every host, starting with the pool
coordinator, then read each host's post-update reboot guidance.

Run it::

    apply_update("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

import XenAPI

from connection import connect
from helpers import enable_when_booted, introduce_update_repositories, wait_for_restart


def apply_update(url, username, password, repo_url, source_url):
    """Sync the pool's update metadata from the CDN, then apply the synced updates to each host,
    coordinator first, as the documentation requires.

    Host.apply_updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks
    for Workload Balancing to be switched off before you start updating - so check both up front and
    stop rather than disabling either for you; turn them back on again once the update is done.
    pool.sync_updates needs at least one repository with update=True enabled
    (NO_REPOSITORY_ENABLED otherwise) - introduce and attach a throwaway one, and forget it again
    afterwards. Applying a batch whose mandatory guidance needs an evacuation fails with
    HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs are moved off first; handle that
    rather than assuming an update batch never asks for one, and resolve any pending mandatory host
    guidance before finishing (it would otherwise block the next apply_updates on that host with
    HOST_PENDING_MANDATORY_GUIDANCES_NOT_EMPTY). Guidance that targets VMs instead of hosts (for
    example restarting a VM) is not handled here."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    if session.xenapi.pool.get_ha_enabled(pool) or session.xenapi.pool.get_wlb_enabled(pool):
        raise RuntimeError("HA and Workload Balancing must both be off before updating the pool; "
                            "disable them, run this again, then re-enable them once it finishes")
    repos = introduce_update_repositories(session, repo_url, source_url)
    # Remember the pool's own repositories, to put them back afterwards.
    previous = session.xenapi.pool.get_repositories(pool)
    session.xenapi.pool.set_repositories(pool, repos)
    try:
        # Sync the pool's update metadata; the returned hash identifies the synced set.
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))

        # Apply the synced updates to each host, coordinator first as the documentation requires.
        # Then read the reboot guidance to decide whether a host needs a reboot.
        hosts = session.xenapi.host.get_all_records()
        master = session.xenapi.pool.get_master(pool)
        ordered_refs = [master] + [ref for ref in hosts if ref != master]
        for host_ref in ordered_refs:
            host = hosts[host_ref]
            try:
                session.xenapi.host.apply_updates(host_ref, hash_)
            except XenAPI.Failure as e:
                if e.details[0] != "HOST_EVACUATION_IS_REQUIRED":
                    raise
                print("  %s: needs evacuating first; evacuating and retrying" % host["name_label"])
                session.xenapi.host.disable(host_ref)
                session.xenapi.host.evacuate(host_ref)
                session.xenapi.host.apply_updates(host_ref, hash_)
                session.xenapi.host.enable(host_ref)
            guidance = session.xenapi.host.get_pending_guidances(host_ref)
            print("  %s: applied; pending guidance = [%s]" % (host["name_label"], ", ".join(guidance)))
            if "reboot_host" in guidance or "restart_toolstack" in guidance:
                # As in rolling-pool-update: either restart returns before it has happened, and the
                # coordinator's takes this session with it - so wait for it, reconnecting.
                key = "boot_time" if "reboot_host" in guidance else "agent_start_time"
                before = session.xenapi.host.get_other_config(host_ref).get(key)
                if key == "boot_time":
                    session.xenapi.host.reboot(host_ref)
                else:
                    session.xenapi.host.restart_agent(host_ref)
                session = wait_for_restart(url, username, password, host["uuid"], key, before)
            # apply_updates disables the host while it works (auto_enable: a restart puts it back) - with
            # no restart to do, nothing re-enables it. Return it to service either way.
            enable_when_booted(session.xenapi, host_ref)
    finally:
        session.xenapi.pool.set_repositories(pool, previous)
        for repo in repos:
            session.xenapi.Repository.forget(repo)
    print("OK: apply-update")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
  sdk-host1: applied; pending guidance = []
  sdk-host2: applied; pending guidance = []
OK: apply-update
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/updates/ApplyUpdate.java`](../../java/src/main/java/com/xenserver/samples/updates/ApplyUpdate.java)

```java
package com.xenserver.samples.updates;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Repository;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.enableWhenBooted;
import static com.xenserver.samples.Helpers.introduceUpdateRepositories;
import static com.xenserver.samples.Helpers.waitForRestart;
import static com.xenserver.samples.PoolConnection.connect;

public final class ApplyUpdate {
    private ApplyUpdate() {
    }

    /**
     * Apply updates from the CDN.
     *
     * <p>Sync the pool's update metadata from the CDN and apply it to every host, starting with the pool
     * coordinator, then read each host's post-update reboot guidance.
     *
     * <p>Host.applyUpdates refuses with HOST_EVACUATION_IS_REQUIRED (handled below) or HA_IS_ENABLED
     * while HA is on, and the documentation also asks for Workload Balancing to be switched off before
     * you start updating - so check both up front and stop rather than disabling either for you; turn
     * them back on again once the update is done.
     *
     * <p>pool.syncUpdates needs at least one repository with update=True enabled (NO_REPOSITORY_ENABLED
     * otherwise) - introduce and attach a throwaway one, and forget it again afterwards. Applying a batch
     * whose mandatory guidance needs an evacuation fails with HOST_EVACUATION_IS_REQUIRED unless the
     * host's resident VMs are moved off first; handle that rather than assuming an update batch never asks
     * for one. Only call host.reboot/host.restart_agent when the RETURNED pending guidance actually
     * contains REBOOT_HOST/RESTART_TOOLSTACK (modern xapi, &gt;=23.18.0, never auto-reboots - it only
     * records guidance) - not unconditionally after every apply. Guidance that targets VMs instead of
     * hosts (for example restarting a VM) is not handled here.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ApplyUpdate.run("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
     * "https://repo-src.ops.xenserver.com/xs9");
     * }</pre>
     */
    public static void run(String url, String user, String password, String repoUrl,
            String sourceUrl) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        if (pool.getHaEnabled(conn) || pool.getWlbEnabled(conn)) {
            throw new RuntimeException("HA and Workload Balancing must both be off before updating the "
                    + "pool; disable them, run this again, then re-enable them once it finishes");
        }
        Set<Repository> repos = introduceUpdateRepositories(conn, repoUrl, sourceUrl);
        // Remember the pool's own repositories, to put them back afterwards.
        Set<Repository> previous = pool.getRepositories(conn);
        pool.setRepositories(conn, repos);
        try {
            // Sync the pool's update metadata; the returned hash identifies the synced set.
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());

            // Apply the synced updates to each host, coordinator first as the documentation requires.
            // Then read the reboot guidance to decide whether a host needs a reboot.
            Map<Host, Host.Record> hosts = Host.getAllRecords(conn);
            Host master = pool.getMaster(conn);
            List<Host> ordered = new ArrayList<>();
            ordered.add(master);
            for (Host h : hosts.keySet()) {
                if (!h.equals(master)) ordered.add(h);
            }
            for (Host host : ordered) {
                Host.Record rec = hosts.get(host);
                try {
                    host.applyUpdates(conn, hash);
                } catch (Types.HostEvacuationIsRequired ex) {
                    System.out.println("  " + rec.nameLabel + ": needs evacuating first; "
                            + "evacuating and retrying");
                    host.disable(conn);
                    host.evacuate(conn);
                    host.applyUpdates(conn, hash);
                    host.enable(conn);
                }
                Set<Types.UpdateGuidances> guidance = host.getPendingGuidances(conn);
                System.out.println("  " + rec.nameLabel + ": applied; pending guidance = " + guidance);
                boolean rebooting = guidance.contains(Types.UpdateGuidances.REBOOT_HOST);
                if (rebooting || guidance.contains(Types.UpdateGuidances.RESTART_TOOLSTACK)) {
                    // As in rolling-pool-update: either restart returns before it has happened, and the
                    // coordinator's takes this connection's session with it - so wait for it, reconnecting.
                    String key = rebooting ? "boot_time" : "agent_start_time";
                    String before = host.getOtherConfig(conn).get(key);
                    if (rebooting) host.reboot(conn);
                    else host.restartAgent(conn);
                    conn = waitForRestart(url, user, password, rec.uuid, key, before);
                }
                // apply_updates disables the host while it works (auto_enable: a restart puts it back) -
                // with no restart to do, nothing re-enables it. Return it to service either way.
                enableWhenBooted(conn, host);
            }
        } finally {
            pool.setRepositories(conn, previous);
            for (Repository repo : repos) repo.forget(conn);
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
  sdk-host2: applied; pending guidance = []
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
// Sync the pool's update metadata from the CDN and apply it to every host, starting with the pool
// coordinator, then read each host's post-update reboot guidance.
//
// Host.ApplyUpdates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
// Workload Balancing to be switched off before you start updating - so check both up front and stop
// rather than disabling either for you; turn them back on again once the update is done.
//
// pool.sync_updates needs at least one repository with update=true enabled
// (NO_REPOSITORY_ENABLED otherwise) - introduce and attach a throwaway one, and forget it again
// afterwards. Applying a batch whose mandatory guidance needs an evacuation fails with
// HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs are moved off first; handle that
// rather than assuming an update batch never asks for one. Guidance that targets VMs instead of
// hosts (for example restarting a VM) is not handled here.
func applyUpdate(url, user, password, repoURL, sourceURL string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	haEnabled, err := xenapi.Pool.GetHaEnabled(session, pool)
	check(err)
	wlbEnabled, err := xenapi.Pool.GetWlbEnabled(session, pool)
	check(err)
	if haEnabled || wlbEnabled {
		panic("HA and Workload Balancing must both be off before updating the pool; disable them, " +
			"run this again, then re-enable them once it finishes")
	}
	repos := introduceUpdateRepositories(session, repoURL, sourceURL)
	// Remember the pool's own repositories, to put them back afterwards.
	previous, perr := xenapi.Pool.GetRepositories(session, pool)
	check(perr)
	check(xenapi.Pool.SetRepositories(session, pool, repos))
	defer func() {
		check(xenapi.Pool.SetRepositories(session, pool, previous))
		for _, repo := range repos {
			check(xenapi.Repository.Forget(session, repo))
		}
	}()

	// Sync the pool's update metadata; the returned hash identifies the synced set.
	hash, err := xenapi.Pool.SyncUpdates5(session, pool, false, "", "")
	check(err)
	fmt.Printf("Synced updates; hash length %d\n", len(hash))

	// Apply the synced updates to each host, coordinator first as the documentation requires.
	// Then read the reboot guidance to decide whether a host needs a reboot.
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	master, err := xenapi.Pool.GetMaster(session, pool)
	check(err)
	orderedRefs := []xenapi.HostRef{master}
	for hostRef := range hosts {
		if hostRef != master {
			orderedRefs = append(orderedRefs, hostRef)
		}
	}
	for _, hostRef := range orderedRefs {
		host := hosts[hostRef]
		if _, err := xenapi.Host.ApplyUpdates(session, hostRef, hash); err != nil {
			if failureCode(err) != xenapi.ErrorHostEvacuationIsRequired {
				panic(err)
			}
			fmt.Printf("  %s: needs evacuating first; evacuating and retrying\n", host.NameLabel)
			check(xenapi.Host.Disable(session, hostRef, true))
			check(xenapi.Host.Evacuate2(session, hostRef))
			_, err := xenapi.Host.ApplyUpdates(session, hostRef, hash)
			check(err)
			check(xenapi.Host.Enable(session, hostRef))
		}
		guidance, _ := xenapi.Host.GetPendingGuidances(session, hostRef)
		fmt.Printf("  %s: applied; pending guidance = %v\n", host.NameLabel, guidance)
		// Modern xapi (>=23.18.0) doesn't reboot a host for you: it only records pending_guidances,
		// so only reboot (or restart the toolstack) when the applied batch actually asks for it.
		rebootHost := containsGuidance(guidance, xenapi.UpdateGuidancesRebootHost)
		if rebootHost || containsGuidance(guidance, xenapi.UpdateGuidancesRestartToolstack) {
			// As in rolling-pool-update: either restart returns before it has happened, and the
			// coordinator's takes this session with it - so wait for it, reconnecting.
			key := "agent_start_time"
			if rebootHost {
				key = "boot_time"
			}
			otherConfig, err := xenapi.Host.GetOtherConfig(session, hostRef)
			check(err)
			before := otherConfig[key]
			if rebootHost {
				check(xenapi.Host.Reboot(session, hostRef))
			} else {
				check(xenapi.Host.RestartAgent(session, hostRef))
			}
			session = waitForRestart(url, user, password, host.UUID, key, before)
		}
		// apply_updates disables the host while it works (auto_enable: a restart puts it back) - with
		// no restart to do, nothing re-enables it. Return it to service either way.
		enableWhenBooted(session, hostRef)
	}
	fmt.Println("OK: apply-update")
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
  sdk-host1: applied; pending guidance = []
  sdk-host2: applied; pending guidance = []
OK: apply-update
```

</details>

## PowerShell

Source: [`powershell/Updates/Invoke-ApplyUpdate.ps1`](../../powershell/Updates/Invoke-ApplyUpdate.ps1)

```powershell
function Invoke-ApplyUpdate {
    <#
    .SYNOPSIS
        Apply updates from the CDN.
    .DESCRIPTION
        Sync the pool's update metadata from the CDN and apply it to every host, starting with the pool
        coordinator, then read each host's post-update reboot guidance.
    .EXAMPLE
        Invoke-ApplyUpdate -Url https://xenserver -UserName root -Password $password `
    .EXAMPLE
        -RepoUrl https://repo.ops.xenserver.com/xs9 -SourceUrl https://repo-src.ops.xenserver.com/xs9
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )
    # ApplyUpdates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
    # Workload Balancing to be switched off before you start updating - so check both up front and stop
    # rather than disabling either for you; turn them back on again once the update is done.
    #
    # pool.sync_updates needs at least one repository with Update enabled (NO_REPOSITORY_ENABLED
    # otherwise) - introduce and attach a throwaway one, and forget it again afterwards. Applying a
    # batch whose mandatory guidance needs an evacuation fails with HOST_EVACUATION_IS_REQUIRED unless
    # the host's resident VMs are moved off first; handle that rather than assuming an update batch
    # never asks for one. Only call Reboot/RestartAgent when the *returned* pending guidance actually
    # contains "reboot_host"/"restart_toolstack" (modern xapi, >=23.18.0, never auto-reboots - it only
    # records guidance) - not unconditionally after every apply. Guidance that targets VMs instead of
    # hosts (for example restarting a VM) is not handled here.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    if ($pool.ha_enabled -or $pool.wlb_enabled) {
        throw "HA and Workload Balancing must both be off before updating the pool; disable them, " +
            "run this again, then re-enable them once it finishes"
    }
    $repos = @(New-UpdateRepositories -Session $session -RepoUrl $RepoUrl -SourceUrl $SourceUrl)
    # Remember the pool's own repositories, to put them back afterwards.
    $previous = @((Get-XenPool -Ref $pool.opaque_ref).repositories | ForEach-Object { $_.opaque_ref })
    $pool | Set-XenPool -Repositories @($repos | ForEach-Object { $_.opaque_ref })
    try {
        # Sync the pool's update metadata; -PassThru returns the hash identifying the synced set.
        $hash = $pool | Invoke-XenPool -XenAction SyncUpdates -PassThru
        Write-Host "Synced updates; hash length $($hash.Length)"

        # Apply the synced updates to each host, coordinator first as the documentation requires (the
        # hash is the action's -Hash parameter). Then read the reboot guidance to decide whether a
        # host needs a reboot.
        $orderedHosts = @($pool.master.opaque_ref) + @(Get-XenHost |
            Where-Object { $_.opaque_ref -ne $pool.master.opaque_ref } | ForEach-Object { $_.opaque_ref })
        foreach ($xenHost in $orderedHosts | ForEach-Object { Get-XenHost -Ref $_ }) {
            try {
                $xenHost | Invoke-XenHost -XenAction ApplyUpdates -Hash $hash
            }
            catch {
                $ex = $_.Exception
                while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
                if (-not ($ex -and $ex.ErrorDescription -and $ex.ErrorDescription[0] -eq "HOST_EVACUATION_IS_REQUIRED")) {
                    throw
                }
                Write-Host "  $($xenHost.name_label): needs evacuating first; evacuating and retrying"
                $xenHost | Invoke-XenHost -XenAction Disable
                Invoke-Evacuate -XenHost $xenHost
                $xenHost | Invoke-XenHost -XenAction ApplyUpdates -Hash $hash
                $xenHost | Invoke-XenHost -XenAction Enable
            }
            $guidance = @((Get-XenHost -Ref $xenHost.opaque_ref).pending_guidances)
            Write-Host "  $($xenHost.name_label): applied; pending guidance = [$($guidance -join ', ')]"
            if ($guidance -contains "reboot_host" -or $guidance -contains "restart_toolstack") {
                # As in rolling-pool-update: either restart returns before it has happened, and the
                # coordinator's takes this session with it - so wait for it, reconnecting.
                $key = if ($guidance -contains "reboot_host") { "boot_time" } else { "agent_start_time" }
                $before = (Get-XenHost -Ref $xenHost.opaque_ref).other_config[$key]
                if ($key -eq "boot_time") {
                    $xenHost | Invoke-XenHost -XenAction Reboot
                }
                else {
                    $xenHost | Invoke-XenHost -XenAction RestartAgent
                }
                $session = Wait-ForRestart -Url $Url -UserName $UserName -Password $Password `
                    -HostUuid $xenHost.uuid -Key $key -Before $before
            }
            # apply_updates disables the host while it works (auto_enable: a restart puts it back) - with no
            # restart to do, nothing re-enables it. Return it to service either way.
            Enable-WhenBooted -XenHost $xenHost
        }
    }
    finally {
        $pool | Set-XenPool -Repositories $previous
        $repos | ForEach-Object { $_ | Invoke-XenRepository -XenAction Forget }
    }
    Write-Host "OK: apply-update"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
  sdk-host1: applied; pending guidance = []
  sdk-host2: applied; pending guidance = []
OK: apply-update
```

</details>

## xe CLI

Source: [`cli/updates/apply-update.sh`](../../cli/updates/apply-update.sh)

```bash
# Apply updates from the CDN.
#
# Sync the pool's update metadata from the CDN and apply it to every host, starting with the pool
# coordinator, then read each host's post-update reboot guidance.
#
# Run it:
#   ./workflows.sh apply-update https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)

# host-apply-updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
# Workload Balancing to be switched off before you start updating - so check both up front and stop
# rather than disabling either for you; turn them back on again once the update is done.
#
# pool-sync-updates needs at least one repository with update=true enabled (NO_REPOSITORY_ENABLED
# otherwise) - introduce the base and update repositories and attach both, remembering what was there to
# put it back afterwards (the "repositories" field is DynamicRO at the API level, but xe's generic
# pool-param-set still writes it - a set reads back "a; b" and is set as "a,b"), forgetting the throwaway
# ones again afterwards. Applying a batch whose mandatory guidance needs an evacuation fails with
# HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs are moved off first; handle that rather than
# assuming an update batch never asks for one. Guidance that targets VMs instead of hosts (for example
# restarting a VM) is not handled here.
apply_update() {
    local repo_url source_url repos repo_list pool master h ordered before hash err guidance
    pool=$(xe pool-list --minimal)
    if [ "$(xe pool-param-get uuid=$pool param-name=ha-enabled)" = "true" ] ||
       [ "$(xe pool-param-get uuid=$pool param-name=wlb-enabled)" = "true" ]; then
        echo "HA and Workload Balancing must both be off before updating the pool; disable them," \
             "run this again, then re-enable them once it finishes" >&2
        exit 1
    fi
    repo_url=$(param repo_url "https://repo.ops.xenserver.com/xs9")
    source_url=$(param source_url "https://repo-src.ops.xenserver.com/xs9")
    repos=$(introduce_update_repositories "$repo_url" "$source_url")
    repo_list=""
    for r in $repos; do repo_list="${repo_list:+$repo_list,}$r"; done
    before=$(xe pool-param-get uuid=$pool param-name=repositories)
    xe pool-param-set uuid=$pool repositories=$repo_list

    hash=$(xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    # Coordinator first, as the documentation requires.
    master=$(xe pool-param-get uuid=$pool param-name=master)
    ordered=$master
    for h in $(each_csv "$(xe host-list --minimal)"); do
        [ "$h" = "$master" ] || ordered="$ordered $h"
    done
    for h in $ordered; do
        if ! err=$(xe host-apply-updates uuid=$h hash=$hash 2>&1); then
            case "$err" in
                *[Ee]vacuat*)
                    echo "  $(xe host-param-get uuid=$h param-name=name-label): needs evacuating first; evacuating and retrying"
                    xe host-disable uuid=$h
                    xe host-evacuate uuid=$h
                    xe host-apply-updates uuid=$h hash=$hash
                    xe host-enable uuid=$h
                    ;;
                *) echo "$err" >&2; exit 1 ;;
            esac
        fi
        guidance=$(set_to_csv "$(xe host-param-get uuid=$h param-name=pending-guidances)")
        echo "  $(xe host-param-get uuid=$h param-name=name-label): applied; pending guidance = [$guidance]"
        # Modern xapi (>=23.18.0) doesn't reboot a host for you: it only records guidance, so only act
        # when the applied batch actually asked for it. A reboot restarts the toolstack too, so
        # reboot_host (checked first) covers restart_toolstack as well; xe has no separate command to
        # restart just the toolstack, so note it rather than silently doing nothing in that rarer case.
        case ",$guidance," in
            *,reboot_host,*)
                # As in rolling-pool-update: the reboot returns before it has happened, and the
                # coordinator's takes the connection with it - so wait for a newer boot time.
                before_key=$(xe host-param-get uuid=$h param-name=other-config param-key=boot_time 2>/dev/null) || true
                xe host-reboot uuid=$h
                wait_for_restart "$h" boot_time "$before_key"
                ;;
            *,restart_toolstack,*) echo "    (restart_toolstack requested; xe has no command for that alone)" ;;
        esac
        # apply-updates disables the host while it works (auto_enable: a restart puts it back) - with no
        # restart to do, nothing re-enables it. Return it to service either way.
        enable_when_booted "$h"
    done
    xe pool-param-set uuid=$pool repositories="${before//; /,}"
    for r in $repos; do xe repository-forget uuid=$r; done
    echo "OK: apply-update"
}
```

<details><summary>Example output</summary>

```text
Synced updates (hash length 64)
  sdk-host1: applied; pending guidance = []
  sdk-host2: applied; pending guidance = []
OK: apply-update
```

</details>
