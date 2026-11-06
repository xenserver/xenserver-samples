<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Rolling pool update

Apply the CDN's updates across the pool host by host, coordinator first: sync the metadata, then for each host apply the updates, moving its VMs to the rest of the pool and rebooting it only when the update requires, so the VMs keep running.

**Requires:** High Availability and Workload Balancing turned off first, as the update documentation describes (turn them back on afterwards).

**Caution:** updates every host, one at a time, moving its VMs off and rebooting it when the update requires.

Workflow `rolling-pool-update`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Updates/Invoke-RollingPoolUpdate.ps1`](../../powershell/Updates/Invoke-RollingPoolUpdate.ps1)

```powershell
function Invoke-RollingPoolUpdate {
    <#
    .SYNOPSIS
        Rolling pool update.
    .DESCRIPTION
        Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in
        turn - coordinator first - apply the updates (evacuating its VMs first only if that turns out to be
        needed), reboot if asked to, and re-enable it — host-by-host orchestration.
    .EXAMPLE
        Invoke-RollingPoolUpdate -Url https://xenserver -UserName root -Password $password `
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
    # Needs an enabled update repository the same way apply-update does - introduce and attach a
    # throwaway one, forget it again afterwards. Modern xapi (>=23.18.0) doesn't reboot a host for you:
    # it only records pending_guidances, so only reboot (or restart the toolstack) when the applied
    # batch actually asks for it, and only evacuate a host first if applying without doing so fails
    # with HOST_EVACUATION_IS_REQUIRED - most updates don't need it. Guidance that targets VMs instead
    # of hosts (for example restarting a VM) is not handled here.
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
        $hash = $pool | Invoke-XenPool -XenAction SyncUpdates -PassThru
        Write-Host "Synced updates; hash length $($hash.Length)"

        # The rolling pattern: apply -> evacuate and retry only if that turns out to be needed ->
        # reboot (only if asked) -> re-enable, one host at a time, coordinator first.
        $orderedHosts = @($pool.master.opaque_ref) + @(Get-XenHost |
            Where-Object { $_.opaque_ref -ne $pool.master.opaque_ref } | ForEach-Object { $_.opaque_ref })
        foreach ($xenHost in $orderedHosts | ForEach-Object { Get-XenHost -Ref $_ }) {
            Write-Host "Updating $($xenHost.name_label):"
            try {
                $xenHost | Invoke-XenHost -XenAction ApplyUpdates -Hash $hash  # apply the synced updates
            }
            catch {
                $ex = $_.Exception
                while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
                if (-not ($ex -and $ex.ErrorDescription -and $ex.ErrorDescription[0] -eq "HOST_EVACUATION_IS_REQUIRED")) {
                    throw
                }
                Write-Host "  needs evacuating first; evacuating and retrying"
                $xenHost | Invoke-XenHost -XenAction Disable    # stop new VMs landing here
                Invoke-Evacuate -XenHost $xenHost               # move running guests to the rest of the pool
                $xenHost | Invoke-XenHost -XenAction ApplyUpdates -Hash $hash
                $xenHost | Invoke-XenHost -XenAction Enable
            }
            $guidance = @((Get-XenHost -Ref $xenHost.opaque_ref).pending_guidances)
            Write-Host "  applied; pending guidance = [$($guidance -join ', ')]"
            if ($guidance -contains "reboot_host" -or $guidance -contains "restart_toolstack") {
                # Either restart returns before it has happened, and if this host is the coordinator it
                # takes this session with it - so note when the host last started, restart it, and
                # reconnect until it reports a newer start and is live again.
                $key = if ($guidance -contains "reboot_host") { "boot_time" } else { "agent_start_time" }
                $before = $xenHost.other_config[$key]
                if ($key -eq "boot_time") {
                    $xenHost | Invoke-XenHost -XenAction Reboot     # reboot into the updated software
                }
                else {
                    $xenHost | Invoke-XenHost -XenAction RestartAgent
                }
                $session = Wait-ForRestart -Url $Url -UserName $UserName -Password $Password `
                    -HostUuid $xenHost.uuid -Key $key -Before $before
            }
            Enable-WhenBooted -XenHost $xenHost   # return the host to service
        }
    }
    finally {
        $pool | Set-XenPool -Repositories $previous
        $repos | ForEach-Object { $_ | Invoke-XenRepository -XenAction Forget }
    }
    Write-Host "OK: rolling-pool-update"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
Updating sdk-host1:
  applied; pending guidance = []
Updating sdk-host2:
  applied; pending guidance = []
OK: rolling-pool-update
```

</details>

## xe CLI

Source: [`cli/updates/rolling-pool-update.sh`](../../cli/updates/rolling-pool-update.sh)

```bash
# Rolling pool update.
#
# Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in
# turn - coordinator first - apply the updates (evacuating its VMs first only if that turns out to be
# needed), reboot if asked to, and re-enable it — host-by-host orchestration.
#
# Run it:
#   ./workflows.sh rolling-pool-update https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)

# host-apply-updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
# Workload Balancing to be switched off before you start updating - so check both up front and stop
# rather than disabling either for you; turn them back on again once the update is done.
#
# Needs an enabled update repository the same way apply-update does - introduce the base and update
# repositories and attach both, forget them again afterwards. Modern xapi (>=23.18.0) doesn't reboot a
# host for you: it only records pending guidance, so only reboot (xe has no remote toolstack-restart
# command, see apply-update) when the applied batch actually asks for it, and only evacuate a host first
# if applying without doing so fails with HOST_EVACUATION_IS_REQUIRED - most updates don't need it.
# Guidance that targets VMs instead of hosts (for example restarting a VM) is not handled here.
rolling_pool_update() {
    local repo_url source_url repos repo_list pool master h ordered before hash err guidance before_key
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
    # pool-sync-updates syncs the pool's ENABLED repositories, and repository-introduce doesn't enable
    # anything (NO_REPOSITORY_ENABLED otherwise). Remember what was there to put it back afterwards. A
    # set reads back "a; b" and is set as "a,b".
    before=$(xe pool-param-get uuid=$pool param-name=repositories)
    xe pool-param-set uuid=$pool repositories=$repo_list
    hash=$(xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    # Rolling pattern: apply -> evacuate and retry only if that turns out to be needed -> reboot (only if
    # asked) -> re-enable, one host at a time, coordinator first.
    master=$(xe pool-param-get uuid=$pool param-name=master)
    ordered=$master
    for h in $(each_csv "$(xe host-list --minimal)"); do
        [ "$h" = "$master" ] || ordered="$ordered $h"
    done
    for h in $ordered; do
        echo "Updating $(xe host-param-get uuid=$h param-name=name-label):"
        if ! err=$(xe host-apply-updates uuid=$h hash=$hash 2>&1); then
            case "$err" in
                *[Ee]vacuat*)
                    echo "  needs evacuating first; evacuating and retrying"
                    xe host-disable uuid=$h
                    xe host-evacuate uuid=$h
                    xe host-apply-updates uuid=$h hash=$hash
                    xe host-enable uuid=$h
                    ;;
                *) echo "$err" >&2; exit 1 ;;
            esac
        fi
        guidance=$(set_to_csv "$(xe host-param-get uuid=$h param-name=pending-guidances)")
        echo "  applied; pending guidance = $guidance"
        case ",$guidance," in
            *,reboot_host,*)
                # The reboot returns before it has happened, and if this host is the coordinator it takes
                # the connection with it - so note when it last booted, reboot it, and wait until it
                # reports a newer boot time and is live again before re-enabling it.
                before_key=$(xe host-param-get uuid=$h param-name=other-config param-key=boot_time 2>/dev/null) || true
                xe host-reboot uuid=$h
                wait_for_restart "$h" boot_time "$before_key"
                ;;
            *,restart_toolstack,*)
                echo "    (restart_toolstack requested; xe has no command for that alone)"
                ;;
        esac
        enable_when_booted "$h"
    done
    xe pool-param-set uuid=$pool repositories="${before//; /,}"
    for r in $repos; do xe repository-forget uuid=$r; done
    echo "OK: rolling-pool-update"
}
```

<details><summary>Example output</summary>

```text
Synced updates (hash length 64)
Updating sdk-host1:
  applied; pending guidance = 
Updating sdk-host2:
  applied; pending guidance = 
OK: rolling-pool-update
```

</details>

## Python

Source: [`python/updates/rolling_pool_update.py`](../../python/updates/rolling_pool_update.py)

```python
"""Rolling pool update.

Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in
turn - coordinator first - apply the updates (evacuating its VMs first only if that turns out to be
needed), reboot if asked to, and re-enable it — host-by-host orchestration.

Run it::

    rolling_pool_update("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

import XenAPI

from connection import connect
from helpers import enable_when_booted, introduce_update_repositories, wait_for_restart


def rolling_pool_update(url, username, password, repo_url, source_url):
    """Apply the CDN's updates host-by-host, coordinator first, so the pool never goes fully offline.

    Host.apply_updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks
    for Workload Balancing to be switched off before you start updating - so check both up front and
    stop rather than disabling either for you; turn them back on again once the update is done.
    Needs an enabled update repository the same way apply-update does - introduce and attach a
    throwaway one, forget it again afterwards. Modern xapi (>=23.18.0) doesn't reboot a host for
    you: it only records pending_guidances, so only reboot (or restart the toolstack) when the
    applied batch actually asks for it, and only evacuate a host first if applying without doing so
    fails with HOST_EVACUATION_IS_REQUIRED - most updates don't need it. Guidance that targets VMs
    instead of hosts (for example restarting a VM) is not handled here."""
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
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))

        # The rolling pattern: apply -> evacuate and retry only if that turns out to be needed ->
        # reboot (only if asked) -> re-enable, one host at a time, coordinator first.
        hosts = session.xenapi.host.get_all_records()
        master = session.xenapi.pool.get_master(pool)
        ordered_refs = [master] + [ref for ref in hosts if ref != master]
        for host_ref in ordered_refs:
            host = hosts[host_ref]
            print("Updating %s:" % host["name_label"])
            try:
                session.xenapi.host.apply_updates(host_ref, hash_)  # apply the synced updates
            except XenAPI.Failure as e:
                if e.details[0] != "HOST_EVACUATION_IS_REQUIRED":
                    raise
                print("  needs evacuating first; evacuating and retrying")
                session.xenapi.host.disable(host_ref)   # stop new VMs landing here
                session.xenapi.host.evacuate(host_ref)  # move running guests to the rest of the pool
                session.xenapi.host.apply_updates(host_ref, hash_)
                session.xenapi.host.enable(host_ref)
            guidance = session.xenapi.host.get_pending_guidances(host_ref)
            print("  applied; pending guidance = [%s]" % ", ".join(guidance))
            if "reboot_host" in guidance or "restart_toolstack" in guidance:
                # Either restart returns before it has happened, and if this host is the coordinator
                # it takes this session with it - so note when the host last started, restart it, and
                # reconnect until it reports a newer start and is live again.
                key = "boot_time" if "reboot_host" in guidance else "agent_start_time"
                before = session.xenapi.host.get_other_config(host_ref).get(key)
                if key == "boot_time":
                    session.xenapi.host.reboot(host_ref)       # reboot into the updated software
                else:
                    session.xenapi.host.restart_agent(host_ref)
                session = wait_for_restart(url, username, password, host["uuid"], key, before)
            enable_when_booted(session.xenapi, host_ref)       # return the host to service
    finally:
        session.xenapi.pool.set_repositories(pool, previous)
        for repo in repos:
            session.xenapi.Repository.forget(repo)
    print("OK: rolling-pool-update")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
Updating sdk-host1:
  applied; pending guidance = []
Updating sdk-host2:
  applied; pending guidance = []
OK: rolling-pool-update
```

</details>

## C# (.NET)

Source: [`csharp/Updates/RollingPoolUpdate.cs`](../../csharp/Updates/RollingPoolUpdate.cs)

```csharp
/// <summary>
/// Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in
/// turn - coordinator first - apply the updates (evacuating its VMs first only if that turns out to be
/// needed), reboot if asked to, and re-enable it — host-by-host orchestration.
/// </summary>
/// <example>
/// <code>
/// Workflows.RollingPoolUpdate("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
/// Workflows."https://repo-src.ops.xenserver.com/xs9");
/// </code>
/// </example>
public static void RollingPoolUpdate(string url, string user, string password, string repoUrl, string sourceUrl)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0].opaque_ref;
    // Host.apply_updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks
    // for Workload Balancing to be switched off before you start updating - so check both up front
    // and stop rather than disabling either for you; turn them back on again once the update is done.
    if (Pool.get_ha_enabled(session, pool) || Pool.get_wlb_enabled(session, pool))
        throw new Exception("HA and Workload Balancing must both be off before updating the pool; " +
                             "disable them, run this again, then re-enable them once it finishes");
    // Needs an enabled update repository the same way apply-update does - introduce and attach a
    // throwaway one, forget it again afterwards.
    var repos = IntroduceUpdateRepositories(session, repoUrl, sourceUrl);
    // Remember the pool's own repositories, to put them back afterwards.
    var previous = Pool.get_repositories(session, pool);
    Pool.set_repositories(session, pool, repos);
    try
    {
        // Sync the pool's update metadata; the returned hash identifies the synced set.
        var hash = Pool.sync_updates(session, pool, false, "", "");
        Console.WriteLine($"Synced updates; hash length {hash.Length}");

        // Apply them host-by-host, coordinator first, so the pool never goes fully offline (the
        // rolling pattern): apply -> evacuate and retry only if that turns out to be needed ->
        // reboot (only if asked) -> re-enable. Modern xapi (>=23.18.0) doesn't reboot a host
        // for you: it only records pending_guidances, so only reboot (or restart the toolstack)
        // when the applied batch actually asks for it. (Guidance that targets VMs instead of
        // hosts, for example restarting a VM, is not handled here.)
        var hosts = Host.get_all_records(session);
        var master = Pool.get_master(session, pool);
        var orderedRefs = new[] { master }.Concat(hosts.Keys.Where(r => r.opaque_ref != master.opaque_ref));
        foreach (var hostRef in orderedRefs)
        {
            var host = hosts[hostRef];
            var h = hostRef.opaque_ref;
            Console.WriteLine($"Updating {host.name_label}:");
            try
            {
                Host.apply_updates(session, h, hash);  // apply the synced updates
            }
            catch (Failure f) when (f.ErrorDescription[0] == "HOST_EVACUATION_IS_REQUIRED")
            {
                Console.WriteLine("  needs evacuating first; evacuating and retrying");
                Host.disable(session, h);   // stop new VMs landing here
                Host.evacuate(session, h);  // move running guests to the rest of the pool
                Host.apply_updates(session, h, hash);
                Host.enable(session, h);
            }
            var guidance = Host.get_pending_guidances(session, h);
            Console.WriteLine($"  applied; pending guidance = [{string.Join(", ", guidance)}]");
            if (guidance.Contains(update_guidances.reboot_host) ||
                guidance.Contains(update_guidances.restart_toolstack))
            {
                // Either restart returns before it has happened, and if this host is the coordinator
                // it takes this session with it - so note when the host last started, restart it, and
                // reconnect until it reports a newer start and is live again.
                var rebooting = guidance.Contains(update_guidances.reboot_host);
                var key = rebooting ? "boot_time" : "agent_start_time";
                Host.get_other_config(session, h).TryGetValue(key, out var before);
                if (rebooting) Host.reboot(session, h);           // reboot into the updated software
                else Host.restart_agent(session, h);
                session = WaitForRestart(url, user, password, host.uuid, key, before);
            }
            EnableWhenBooted(session, h);          // return the host to service
        }
    }
    finally
    {
        Pool.set_repositories(session, pool, previous);
        foreach (var repo in repos) Repository.forget(session, repo.opaque_ref);
    }
    Console.WriteLine("OK: rolling-pool-update");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
Updating sdk-host1:
  applied; pending guidance = []
Updating sdk-host2:
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

	"go/xenapi"
)

// rollingPoolUpdate applies the CDN's updates host-by-host, coordinator first, so the pool never
// goes fully offline.
//
// Host.ApplyUpdates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
// Workload Balancing to be switched off before you start updating - so check both up front and stop
// rather than disabling either for you; turn them back on again once the update is done.
//
// Needs an enabled update repository the same way apply-update does - introduce and attach a
// throwaway one, forget it again afterwards. Modern xapi (>=23.18.0) doesn't reboot a host for you:
// it only records pending_guidances, so only reboot (or restart the toolstack) when the applied
// batch actually asks for it, and only evacuate a host first if applying without doing so fails
// with HOST_EVACUATION_IS_REQUIRED - most updates don't need it. Guidance that targets VMs instead
// of hosts (for example restarting a VM) is not handled here.
func rollingPoolUpdate(url, user, password, repoURL, sourceURL string) {
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

	hash, err := xenapi.Pool.SyncUpdates5(session, pool, false, "", "")
	check(err)
	fmt.Printf("Synced updates; hash length %d\n", len(hash))

	// The rolling pattern: apply -> evacuate and retry only if that turns out to be needed ->
	// reboot (only if asked) -> re-enable, one host at a time, coordinator first.
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
		fmt.Printf("Updating %s:\n", host.NameLabel)
		if _, err := xenapi.Host.ApplyUpdates(session, hostRef, hash); err != nil {
			if failureCode(err) != xenapi.ErrorHostEvacuationIsRequired {
				panic(err)
			}
			fmt.Println("  needs evacuating first; evacuating and retrying")
			check(xenapi.Host.Disable(session, hostRef, true)) // stop new VMs landing here
			check(xenapi.Host.Evacuate2(session, hostRef))     // move running guests to the rest of the pool
			_, err := xenapi.Host.ApplyUpdates(session, hostRef, hash)
			check(err)
			check(xenapi.Host.Enable(session, hostRef))
		}
		guidance, _ := xenapi.Host.GetPendingGuidances(session, hostRef)
		fmt.Printf("  applied; pending guidance = %v\n", guidance)
		rebootHost := containsGuidance(guidance, xenapi.UpdateGuidancesRebootHost)
		restartToolstack := containsGuidance(guidance, xenapi.UpdateGuidancesRestartToolstack)
		if rebootHost || restartToolstack {
			// Either restart returns before it has happened, and if this host is the coordinator it
			// takes this session with it - so note when the host last started, restart it, and
			// reconnect until it reports a newer start and is live again.
			key := "agent_start_time"
			if rebootHost {
				key = "boot_time"
			}
			otherConfig, err := xenapi.Host.GetOtherConfig(session, hostRef)
			check(err)
			before := otherConfig[key]
			if rebootHost {
				check(xenapi.Host.Reboot(session, hostRef)) // reboot into the updated software
			} else {
				check(xenapi.Host.RestartAgent(session, hostRef))
			}
			session = waitForRestart(url, user, password, host.UUID, key, before)
		}
		enableWhenBooted(session, hostRef) // return the host to service
	}
	fmt.Println("OK: rolling-pool-update")
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
Updating sdk-host1:
  applied; pending guidance = []
Updating sdk-host2:
  applied; pending guidance = []
OK: rolling-pool-update
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/updates/RollingPoolUpdate.java`](../../java/src/main/java/com/xenserver/samples/updates/RollingPoolUpdate.java)

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

public final class RollingPoolUpdate {
    private RollingPoolUpdate() {
    }

    /**
     * Rolling pool update.
     *
     * <p>Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host
     * in turn - coordinator first - apply the updates (evacuating its VMs first only if that turns out to
     * be needed), reboot if asked to, and re-enable it — host-by-host orchestration.
     *
     * <p>Host.applyUpdates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
     * Workload Balancing to be switched off before you start updating - so check both up front and stop
     * rather than disabling either for you; turn them back on again once the update is done.
     *
     * <p>Needs an enabled update repository the same way apply-update does - introduce and attach a
     * throwaway one, forget it again afterwards. Modern xapi (&gt;=23.18.0) doesn't reboot a host for you:
     * it only records pending guidance, so only reboot (or restart the toolstack) when the applied batch
     * actually asks for it, and only evacuate a host first if applying without doing so fails with
     * HOST_EVACUATION_IS_REQUIRED - most updates don't need it. Guidance that targets VMs instead of hosts
     * (for example restarting a VM) is not handled here.
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
        if (pool.getHaEnabled(conn) || pool.getWlbEnabled(conn)) {
            throw new RuntimeException("HA and Workload Balancing must both be off before updating the "
                    + "pool; disable them, run this again, then re-enable them once it finishes");
        }
        Set<Repository> repos = introduceUpdateRepositories(conn, repoUrl, sourceUrl);
        // Remember the pool's own repositories, to put them back afterwards.
        Set<Repository> previous = pool.getRepositories(conn);
        pool.setRepositories(conn, repos);
        try {
            String hash = pool.syncUpdates(conn, false, "", "");
            System.out.println("Synced updates; hash length " + hash.length());

            // The rolling pattern: apply -> evacuate and retry only if that turns out to be needed ->
            // reboot (only if asked) -> re-enable, one host at a time, coordinator first.
            Map<Host, Host.Record> hosts = Host.getAllRecords(conn);
            Host master = pool.getMaster(conn);
            List<Host> ordered = new ArrayList<>();
            ordered.add(master);
            for (Host h : hosts.keySet()) {
                if (!h.equals(master)) ordered.add(h);
            }
            for (Host host : ordered) {
                Host.Record rec = hosts.get(host);
                System.out.println("Updating " + rec.nameLabel + ":");
                try {
                    host.applyUpdates(conn, hash); // apply the synced updates
                } catch (Types.HostEvacuationIsRequired ex) {
                    System.out.println("  needs evacuating first; evacuating and retrying");
                    host.disable(conn);            // stop new VMs landing here
                    host.evacuate(conn);           // move running guests to the rest of the pool
                    host.applyUpdates(conn, hash);
                    host.enable(conn);
                }
                Set<Types.UpdateGuidances> guidance = host.getPendingGuidances(conn);
                System.out.println("  applied; pending guidance = " + guidance);
                if (guidance.contains(Types.UpdateGuidances.REBOOT_HOST)
                        || guidance.contains(Types.UpdateGuidances.RESTART_TOOLSTACK)) {
                    // Either restart returns before it has happened, and if this host is the coordinator
                    // it takes this connection with it - so note when the host last started, restart it,
                    // and reconnect until it reports a newer start and is live again.
                    boolean reboot = guidance.contains(Types.UpdateGuidances.REBOOT_HOST);
                    String key = reboot ? "boot_time" : "agent_start_time";
                    String before = host.getOtherConfig(conn).get(key);
                    if (reboot) {
                        host.reboot(conn);     // reboot into the updated software
                    } else {
                        host.restartAgent(conn);
                    }
                    conn = waitForRestart(url, user, password, rec.uuid, key, before);
                }
                enableWhenBooted(conn, host);  // return the host to service
            }
        } finally {
            pool.setRepositories(conn, previous);
            for (Repository repo : repos) repo.forget(conn);
        }
        System.out.println("OK: rolling-pool-update");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Synced updates; hash length 64
Updating sdk-host1:
  applied; pending guidance = []
Updating sdk-host2:
  applied; pending guidance = []
OK: rolling-pool-update
```

</details>
