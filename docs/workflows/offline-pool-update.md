<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Update an air-gapped pool from a bundle

Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make a bundle repository the pool's update repository, upload the bundle, list the updates it offers, then apply them host by host - coordinator first, moving each host's VMs to the rest of the pool - so the VMs keep running.

**Requires:** an update bundle for the pool's XenServer release, High Availability and Workload Balancing turned off first (turn them back on afterwards), and every running VM able to move to another host.

**Caution:** updates every host, one at a time, moving its VMs to the other hosts and restarting it if the update requires.

Workflow `offline-pool-update`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Updates/Invoke-OfflinePoolUpdate.ps1`](../../powershell/Updates/Invoke-OfflinePoolUpdate.ps1)

```powershell
function Invoke-OfflinePoolUpdate {
    <#
    .SYNOPSIS
        Update an air-gapped pool from a bundle.
    .DESCRIPTION
        Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make a
        bundle repository the pool's update repository, upload the bundle, list the updates it offers, then
        apply them host by host - coordinator first, moving each host's VMs to the rest of the pool - so the
        VMs keep running throughout.

        Check first, before changing anything, that the update can go through: HA and Workload Balancing off,
        no host or VM with mandatory guidance still pending from an earlier update, and every host able to
        empty. Then make a repository of the bundle kind the pool's only enabled repository - a pool can have
        only one (introducing a second fails with BUNDLE_REPOSITORY_ALREADY_EXISTS), so use the existing one
        if there is one.

        Send-XenBundle uploads the bundle with a task to report on: the pool unpacks the bundle, checks its
        signature and syncs its updates before the task completes. Receive-XenUpdates then lists what the
        bundle offers and the hash to apply it with, and Update-Hosts applies it to each host in turn as
        Invoke-RollingPoolUpdate does. Finally report the guidance left for VMs, such as restarting one to
        pick the update up - that is the VM owner's call.

        A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts the
        pool's previous repositories back afterwards so that it can run again on a test pool.
    .EXAMPLE
        Invoke-OfflinePoolUpdate -Url https://xenserver -UserName root -Password $password -BundlePath .\XS9-update.xsbundle
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$BundlePath
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    $hosts = Get-HostsCoordinatorFirst
    Assert-HaAndWlbOff -Pool $pool
    Assert-NoPendingGuidance
    Assert-HostsCanBeEvacuated -Hosts $hosts

    $previous = @($pool.repositories)
    $existing = Get-XenRepository | Where-Object { $_.origin -eq 'bundle' } | Select-Object -First 1
    $repo = if ($existing) { $existing } else {
        # Repository.introduce_bundle is a static-style create, so pass the NULL ref for the (ignored)
        # instance param.
        Invoke-XenRepository -Ref 'OpaqueRef:NULL' -XenAction IntroduceBundle -NameLabel "sdk-example-offline" `
            -NameDescription "Updates from uploaded bundles" -PassThru
    }
    try {
        $pool | Set-XenPool -Repositories @($repo)
        Write-Host ("Pool repositories: " + ((Get-XenPool -Ref $pool).repositories |
            ForEach-Object { (Get-XenRepository -Ref $_).name_label }) -join ", ")

        $coordinator = Get-XenHost -Ref $pool.master
        # Send-XenBundle/Receive-XenUpdates are HTTP helpers, not XenAPI calls: -TaskRef travels in the
        # request itself, so it needs the opaque ref string, not the task object.
        $task = New-XenTask -Label "sdk-example-bundle-upload" -Description "" -PassThru
        try {
            Send-XenBundle -XenHost $coordinator.address -Path $BundlePath -TaskRef $task.opaque_ref `
                -NoWarnCertificates -NoWarnNewCertificates
            $task | Wait-XenTask -ShowProgress
            $finished = Get-XenTask -Ref $task
            if ($finished.status -ne 'success') { throw "bundle upload failed: $($finished.error_info -join ' ')" }
        }
        finally {
            Remove-XenTask -Ref $task
        }
        Write-Host "Uploaded $(Split-Path $BundlePath -Leaf)"

        $json = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-updates-$([guid]::NewGuid().Guid).json"
        $task = New-XenTask -Label "sdk-example-updates" -Description "" -PassThru
        try {
            Receive-XenUpdates -XenHost $coordinator.address -Path $json -TaskRef $task.opaque_ref `
                -NoWarnCertificates -NoWarnNewCertificates
            $task | Wait-XenTask
        }
        finally {
            Remove-XenTask -Ref $task
        }
        $available = Get-Content -Raw -Path $json | ConvertFrom-Json
        Remove-Item $json
        $updates = @($available.updates)
        Write-Host "Updates in the bundle: $($updates.Count)"
        foreach ($update in $updates) { Write-Host "  $($update.id): $($update.summary)" }
        if ($updates.Count -gt 0) {
            $session = Update-Hosts -Session $session -Url $Url -UserName $UserName -Password $Password `
                -Hosts $hosts -Hash $available.hash
        }
    }
    finally {
        # Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
        $pool | Set-XenPool -Repositories $previous
        if (-not $existing) { $repo | Invoke-XenRepository -XenAction Forget }
    }
    Write-VmGuidance
    Write-Host "OK: offline-pool-update"
    $session | Disconnect-XenServer
}
```

## xe CLI

Source: [`cli/updates/offline-pool-update.sh`](../../cli/updates/offline-pool-update.sh)

```bash
# Update an air-gapped pool from a bundle.
#
# Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make a
# bundle repository the pool's update repository, upload the bundle, then apply its updates host by host -
# coordinator first, moving each host's VMs to the rest of the pool - so the VMs keep running throughout.
#
# Run it:
#   ./workflows.sh offline-pool-update https://xenserver root "$password" bundle_path=XS9-update.xsbundle
#
# Optional key=value arguments (default):
#   bundle_path (XS9-update.xsbundle)

# Check first, before changing anything, that the update can go through: HA and Workload Balancing off, no
# host or VM with mandatory guidance still pending from an earlier update, and every host able to empty.
# Then make a repository of the bundle kind the pool's only enabled repository - a pool can have only one
# (introducing a second fails), so use the existing one if there is one. pool-sync-bundle uploads the
# bundle to the coordinator, which unpacks it, checks its signature and syncs its updates; xe waits for that
# to finish. The updates themselves are listed only over HTTP (GET /updates), which xe cannot read, but
# each host's latest-synced-updates-applied says whether it has any to apply ("no") - so update_hosts
# updates just those, as rolling-pool-update does, with the repository's hash. Finally report the guidance
# left for VMs, such as restarting one to pick the update up - that is the VM owner's call.
#
# A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts the
# pool's previous repositories back afterwards so that it can run again on a test pool.
offline_pool_update() {
    local bundle_path hosts h to_update
    bundle_path=$(param bundle_path "XS9-update.xsbundle")
    pool=$(remote_xe pool-list --minimal)
    hosts=$(hosts_coordinator_first)
    check_ha_and_wlb_off
    check_no_pending_guidance
    check_hosts_can_be_evacuated $hosts

    # Remember the pool's own repositories, to put them back afterwards. A set reads back "a; b".
    # Not local (nor is pool): the EXIT trap below reads them after this function has returned.
    before=$(remote_xe pool-param-get uuid=$pool param-name=repositories)
    existing=$(remote_xe repository-list origin=bundle --minimal)
    if [ -n "$existing" ]; then
        repo=$(first_csv "$existing")
    else
        repo=$(remote_xe repository-introduce-bundle name-label=sdk-example-offline \
            name-description="Updates from uploaded bundles")
    fi
    # Forgetting a repository the pool still has enabled fails: restore the pool's own first, however
    # the rest of this goes.
    trap 'remote_xe_try pool-param-set uuid=$pool repositories="$(set_to_csv "$before")"; [ -n "$existing" ] || remote_xe_try repository-forget uuid=$repo' EXIT
    remote_xe pool-param-set uuid=$pool repositories=$repo
    echo "Pool repositories: $(remote_xe repository-param-get uuid=$repo param-name=name-label)"

    remote_xe pool-sync-bundle filename="$bundle_path"
    echo "Uploaded $(basename "$bundle_path")"
    to_update=""
    for h in $hosts; do
        [ "$(remote_xe host-param-get uuid=$h param-name=latest-synced-updates-applied)" = "no" ] &&
            to_update="$to_update $h"
    done
    echo "Hosts with updates to apply: $(echo $to_update | wc -w)"
    [ -z "$to_update" ] || update_hosts "$(remote_xe repository-param-get uuid=$repo param-name=hash)" $to_update
    report_vm_guidance
    ok offline-pool-update
}
```

## Python

Source: [`python/updates/offline_pool_update.py`](../../python/updates/offline_pool_update.py)

```python
"""Update an air-gapped pool from a bundle.

Update a pool that has no internet access from an update bundle (.xsbundle) downloaded elsewhere: make
a bundle repository the pool's update repository, upload the bundle, list the updates it offers, then
apply them host by host - coordinator first, moving each host's VMs to the rest of the pool - so the
VMs keep running throughout.

Run it::

    offline_pool_update("https://xenserver", "root", password, bundle_path="XS9-update.xsbundle")
"""

import json
import os
import ssl
import time
import urllib.request

from connection import connect
from helpers import (check_ha_and_wlb_off, check_hosts_can_be_evacuated, check_no_pending_guidance,
                     hosts_coordinator_first, report_vm_guidance, update_hosts)


def offline_pool_update(url, username, password, bundle_path):
    """Update every host in the pool from the update bundle at bundle_path.

    Check first, before changing anything, that the update can go through: HA and Workload Balancing
    off, no host or VM with mandatory guidance still pending from an earlier update, and every host
    able to empty. Then make a repository of the bundle kind the pool's only enabled repository - a
    pool can have only one (Repository.introduce_bundle refuses a second with
    BUNDLE_REPOSITORY_ALREADY_EXISTS), so use the existing one if there is one.

    Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a task in the query
    string. The server answers 200 before it has read the bundle, so the task says how it went: the pool
    unpacks the bundle, checks its signature and syncs its updates before the task completes. GET
    /updates then lists what the bundle offers and the hash to apply it with, and
    helpers.update_hosts applies it to each host in turn as rolling-pool-update does. Finally report
    the guidance left for VMs, such as restarting one to pick the update up - that is the VM owner's
    call.

    A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts
    the pool's previous repositories back afterwards so that it can run again on a test pool."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]
    ctx = ssl._create_unverified_context()
    hosts = hosts_coordinator_first(session)
    check_ha_and_wlb_off(session, pool)
    check_no_pending_guidance(session)
    check_hosts_can_be_evacuated(session, hosts)

    previous = x.pool.get_repositories(pool)
    existing = [r for r, rec in x.Repository.get_all_records().items() if rec["origin"] == "bundle"]
    repo = existing[0] if existing else x.Repository.introduce_bundle("sdk-example-offline",
                                                                      "Updates from uploaded bundles")
    try:
        x.pool.set_repositories(pool, [repo])
        print("Pool repositories: %s" % ", ".join(x.Repository.get_name_label(r)
                                                  for r in x.pool.get_repositories(pool)))

        task = x.task.create("sdk-example-bundle-upload", "")
        try:
            with open(bundle_path, "rb") as f:
                request = urllib.request.Request(
                    "%s/bundle?session_id=%s&task_id=%s" % (url, session._session, task), data=f,
                    method="PUT", headers={"Content-Length": str(os.path.getsize(bundle_path))})
                urllib.request.urlopen(request, context=ctx).read()
            while x.task.get_status(task) == "pending":
                time.sleep(1)
            if x.task.get_status(task) != "success":
                raise RuntimeError("bundle upload failed: %s" % x.task.get_error_info(task))
        finally:
            x.task.destroy(task)
        print("Uploaded %s" % os.path.basename(bundle_path))

        with urllib.request.urlopen("%s/updates?session_id=%s" % (url, session._session),
                                    context=ctx) as response:
            available = json.loads(response.read())
        updates = available.get("updates", [])
        print("Updates in the bundle: %d" % len(updates))
        for update in updates:
            print("  %s: %s" % (update.get("id", ""), update.get("summary", "")))
        if updates:
            session = update_hosts(session, url, username, password, hosts, available["hash"])
    finally:
        # Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
        session.xenapi.pool.set_repositories(pool, previous)
        if not existing:
            session.xenapi.Repository.forget(repo)
    report_vm_guidance(session)
    print("OK: offline-pool-update")
    session.xenapi.session.logout()
```

## C# (.NET)

Source: [`csharp/Updates/OfflinePoolUpdate.cs`](../../csharp/Updates/OfflinePoolUpdate.cs)

```csharp
/// <summary>
/// Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make a
/// bundle repository the pool's update repository, upload the bundle, list the updates it offers, then
/// apply them host by host - coordinator first, moving each host's VMs to the rest of the pool - so the
/// VMs keep running throughout.
/// </summary>
/// <example>
/// <code>
/// Workflows.OfflinePoolUpdate("https://xenserver", "root", password, "XS9-update.xsbundle");
/// </code>
/// </example>
/// <remarks>
/// Check first, before changing anything, that the update can go through: HA and Workload Balancing off,
/// no host or VM with mandatory guidance still pending from an earlier update, and every host able to
/// empty. Then make a repository of the bundle kind the pool's only enabled repository - a pool can have
/// only one (Repository.introduce_bundle refuses a second with BUNDLE_REPOSITORY_ALREADY_EXISTS), so use
/// the existing one if there is one.
///
/// Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a task in the query
/// string. The server answers 200 before it has read the bundle, so the task says how it went: the pool
/// unpacks the bundle, checks its signature and syncs its updates before the task completes. GET /updates
/// then lists what the bundle offers and the hash to apply it with, and UpdateHosts applies it to each
/// host in turn as rolling-pool-update does. Finally report the guidance left for VMs, such as
/// restarting one to pick the update up - that is the VM owner's call.
///
/// A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts the
/// pool's previous repositories back afterwards so that it can run again on a test pool.
/// </remarks>
public static void OfflinePoolUpdate(string url, string user, string password, string bundlePath)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0];
    var hosts = HostsCoordinatorFirst(session);
    CheckHaAndWlbOff(session, pool);
    CheckNoPendingGuidance(session);
    CheckHostsCanBeEvacuated(session, hosts);

    var previous = Pool.get_repositories(session, pool);
    var existing = Repository.get_all_records(session)
        .Where(kv => kv.Value.origin == origin.bundle).Select(kv => kv.Key).FirstOrDefault();
    var repo = existing ?? Repository.introduce_bundle(session, "sdk-example-offline",
        "Updates from uploaded bundles");
    try
    {
        Pool.set_repositories(session, pool, new() { repo });
        Console.WriteLine("Pool repositories: " + string.Join(", ",
            Pool.get_repositories(session, pool).Select(r => Repository.get_name_label(session, r))));

        var task = Task.create(session, "sdk-example-bundle-upload", "").opaque_ref;
        try
        {
            using var client = InsecureHttpClient();
            using var file = File.OpenRead(bundlePath);
            client.PutAsync($"{url}/bundle?session_id={session.opaque_ref}&task_id={task}",
                new StreamContent(file)).Result.EnsureSuccessStatusCode();
            while (Task.get_status(session, task) == task_status_type.pending)
                System.Threading.Thread.Sleep(1000);
            if (Task.get_status(session, task) != task_status_type.success)
                throw new InvalidOperationException("bundle upload failed: " +
                                    string.Join(", ", Task.get_error_info(session, task)));
        }
        finally
        {
            Task.destroy(session, task);
        }
        Console.WriteLine($"Uploaded {Path.GetFileName(bundlePath)}");

        string hash;
        int count;
        using (var client = InsecureHttpClient())
        using (var available = JsonDocument.Parse(
                   client.GetStringAsync($"{url}/updates?session_id={session.opaque_ref}").Result))
        {
            var root = available.RootElement;
            var updates = root.GetProperty("updates");
            count = updates.GetArrayLength();
            hash = root.GetProperty("hash").GetString();
            Console.WriteLine($"Updates in the bundle: {count}");
            foreach (var update in updates.EnumerateArray())
                Console.WriteLine($"  {update.GetProperty("id").GetString()}: {update.GetProperty("summary").GetString()}");
        }
        if (count > 0)
            session = UpdateHosts(session, url, user, password, hosts, hash);
    }
    finally
    {
        // Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
        Pool.set_repositories(session, pool, previous);
        if (existing == null) Repository.forget(session, repo);
    }
    ReportVmGuidance(session);
    Console.WriteLine("OK: offline-pool-update");
    session.logout();
}
```

## Go

Source: [`go/offline_pool_update.go`](../../go/offline_pool_update.go)

```go
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"go/xenapi"
)

// offlinePoolUpdate - Update an air-gapped pool from a bundle.
//
// Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make
// a bundle repository the pool's update repository, upload the bundle, list the updates it offers,
// then apply them host by host - coordinator first, moving each host's VMs to the rest of the pool -
// so the VMs keep running throughout.
//
// Check first, before changing anything, that the update can go through: HA and Workload Balancing
// off, no host or VM with mandatory guidance still pending from an earlier update, and every host
// able to empty. Then make a repository of the bundle kind the pool's only enabled repository - a
// pool can have only one (Repository.IntroduceBundle refuses a second with
// BUNDLE_REPOSITORY_ALREADY_EXISTS), so use the existing one if there is one. uploadBundle uploads
// the bundle and lists what it offers, and updateHosts applies it to each host in turn as
// rolling-pool-update does. Finally report the guidance left for VMs, such as restarting one to pick
// the update up - that is the VM owner's call.
//
// A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts the
// pool's previous repositories back afterwards so that it can run again on a test pool.
func offlinePoolUpdate(url, user, password, bundlePath string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	hosts := hostsCoordinatorFirst(session)
	checkHaAndWlbOff(session, pool)
	checkNoPendingGuidance(session)
	checkHostsCanBeEvacuated(session, hosts)

	previous, err := xenapi.Pool.GetRepositories(session, pool)
	check(err)
	repos, err := xenapi.Repository.GetAllRecords(session)
	check(err)
	var repo xenapi.RepositoryRef
	for ref, record := range repos {
		if record.Origin == xenapi.OriginBundle {
			repo = ref
		}
	}
	introduced := repo == ""
	if introduced {
		repo, err = xenapi.Repository.IntroduceBundle(session, "sdk-example-offline", "Updates from uploaded bundles")
		check(err)
	}
	defer func() {
		// Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
		check(xenapi.Pool.SetRepositories(session, pool, previous))
		if introduced {
			check(xenapi.Repository.Forget(session, repo))
		}
	}()

	check(xenapi.Pool.SetRepositories(session, pool, []xenapi.RepositoryRef{repo}))
	enabled, err := xenapi.Pool.GetRepositories(session, pool)
	check(err)
	for _, r := range enabled {
		name, _ := xenapi.Repository.GetNameLabel(session, r)
		fmt.Printf("Pool repositories: %s\n", name)
	}

	hash, count := uploadBundle(session, url, user, password, bundlePath)
	if count > 0 {
		session = updateHosts(session, url, user, password, hosts, hash)
	}
	reportVMGuidance(session)
	fmt.Println("OK: offline-pool-update")
}

// uploadBundle uploads the bundle at bundlePath to the pool's bundle repository, prints the updates it
// offers, and returns the hash to apply them with and how many there are.
//
// Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a task in the query
// string. The server answers 200 before it has read the bundle, so the task says how it went: the
// pool unpacks the bundle, checks its signature and syncs its updates before the task completes. GET
// /updates then lists what the bundle offers and the hash to apply it with.
func uploadBundle(session *xenapi.Session, url, user, password, bundlePath string) (string, int) {
	// The Go binding keeps its own session id private, so log in once more for the HTTP transfers -
	// and out again here, before any host restarts.
	sid := rawLogin(url, user, password)
	defer rawRPC(url, "session.logout", sid)
	task, err := xenapi.Task.Create(session, "sdk-example-bundle-upload", "")
	check(err)
	defer xenapi.Task.Destroy(session, task)
	bundle, err := os.Open(bundlePath)
	check(err)
	defer bundle.Close()
	info, err := bundle.Stat()
	check(err)
	request, err := http.NewRequest(http.MethodPut,
		fmt.Sprintf("%s/bundle?session_id=%s&task_id=%s", url, sid, task), bundle)
	check(err)
	request.ContentLength = info.Size()
	response, err := insecureClient().Do(request)
	check(err)
	io.Copy(io.Discard, response.Body)
	response.Body.Close()
	for {
		status, err := xenapi.Task.GetStatus(session, task)
		check(err)
		if status != xenapi.TaskStatusTypePending {
			break
		}
		time.Sleep(time.Second)
	}
	if status, _ := xenapi.Task.GetStatus(session, task); status != xenapi.TaskStatusTypeSuccess {
		errInfo, _ := xenapi.Task.GetErrorInfo(session, task)
		panic(fmt.Sprintf("bundle upload failed: %v", errInfo))
	}
	fmt.Printf("Uploaded %s\n", filepath.Base(bundlePath))

	response, err = insecureClient().Get(fmt.Sprintf("%s/updates?session_id=%s", url, sid))
	check(err)
	defer response.Body.Close()
	var available struct {
		Hash    string `json:"hash"`
		Updates []struct {
			ID      string `json:"id"`
			Summary string `json:"summary"`
		} `json:"updates"`
	}
	check(json.NewDecoder(response.Body).Decode(&available))
	fmt.Printf("Updates in the bundle: %d\n", len(available.Updates))
	for _, update := range available.Updates {
		fmt.Printf("  %s: %s\n", update.ID, update.Summary)
	}
	return available.Hash, len(available.Updates)
}
```

## Java

Source: [`java/src/main/java/com/xenserver/samples/updates/OfflinePoolUpdate.java`](../../java/src/main/java/com/xenserver/samples/updates/OfflinePoolUpdate.java)

```java
package com.xenserver.samples.updates;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Repository;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;
import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.classic.methods.HttpPut;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.EntityUtils;
import org.apache.hc.core5.http.io.entity.FileEntity;

import java.io.File;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.checkHaAndWlbOff;
import static com.xenserver.samples.Helpers.checkHostsCanBeEvacuated;
import static com.xenserver.samples.Helpers.checkNoPendingGuidance;
import static com.xenserver.samples.Helpers.hostsCoordinatorFirst;
import static com.xenserver.samples.Helpers.reportVmGuidance;
import static com.xenserver.samples.Helpers.updateHosts;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class OfflinePoolUpdate {
    private OfflinePoolUpdate() {
    }

    /**
     * Update an air-gapped pool from a bundle.
     *
     * <p>Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make
     * a bundle repository the pool's update repository, upload the bundle, list the updates it offers, then
     * apply them host by host - coordinator first, moving each host's VMs to the rest of the pool - so the
     * VMs keep running throughout.
     *
     * <p>Check first, before changing anything, that the update can go through: HA and Workload Balancing
     * off, no host or VM with mandatory guidance still pending from an earlier update, and every host able
     * to empty. Then make a repository of the bundle kind the pool's only enabled repository - a pool can
     * have only one (Repository.introduceBundle refuses a second with BUNDLE_REPOSITORY_ALREADY_EXISTS), so
     * use the existing one if there is one.
     *
     * <p>Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a task in the query
     * string. The server answers 200 before it has read the bundle, so the task says how it went: the pool
     * unpacks the bundle, checks its signature and syncs its updates before the task completes. GET
     * /updates then lists what the bundle offers and the hash to apply it with, and Helpers.updateHosts
     * applies it to each host in turn as RollingPoolUpdate does. Finally report the guidance left for VMs,
     * such as restarting one to pick the update up - that is the VM owner's call.
     *
     * <p>A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts the
     * pool's previous repositories back afterwards so that it can run again on a test pool.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * OfflinePoolUpdate.run("https://xenserver", "root", password, "XS9-update.xsbundle");
     * }</pre>
     */
    public static void run(String url, String user, String password, String bundlePath) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        List<Host> hosts = hostsCoordinatorFirst(conn);
        checkHaAndWlbOff(conn, pool);
        checkNoPendingGuidance(conn);
        checkHostsCanBeEvacuated(conn, hosts);

        Set<Repository> previous = pool.getRepositories(conn);
        Repository existing = null;
        for (Map.Entry<Repository, Repository.Record> e : Repository.getAllRecords(conn).entrySet())
            if (e.getValue().origin == Types.Origin.BUNDLE) existing = e.getKey();
        Repository repo = existing != null ? existing
            : Repository.introduceBundle(conn, "sdk-example-offline", "Updates from uploaded bundles");
        try {
            pool.setRepositories(conn, Set.of(repo));
            for (Repository r : pool.getRepositories(conn))
                System.out.println("Pool repositories: " + r.getNameLabel(conn));

            String session = conn.getSessionReference();
            Task task = Task.create(conn, "sdk-example-bundle-upload", "");
            try {
                HttpPut put = new HttpPut(url + "/bundle?session_id=" + session + "&task_id=" + task.toWireString());
                put.setEntity(new FileEntity(new File(bundlePath), null));
                try (CloseableHttpClient http = trustingHttpClient()) {
                    http.execute(put, response -> EntityUtils.toString(response.getEntity()));
                }
                while (task.getStatus(conn) == Types.TaskStatusType.PENDING) Thread.sleep(1000);
                if (task.getStatus(conn) != Types.TaskStatusType.SUCCESS)
                    throw new IllegalStateException("bundle upload failed: " + task.getErrorInfo(conn));
            } finally {
                task.destroy(conn);
            }
            System.out.println("Uploaded " + new File(bundlePath).getName());

            String json;
            try (CloseableHttpClient http = trustingHttpClient()) {
                json = http.execute(new HttpGet(url + "/updates?session_id=" + session),
                    response -> EntityUtils.toString(response.getEntity()));
            }
            JsonNode available = new ObjectMapper().readTree(json);
            JsonNode updates = available.path("updates");
            System.out.println("Updates in the bundle: " + updates.size());
            for (JsonNode update : updates)
                System.out.println("  " + update.path("id").asText() + ": " + update.path("summary").asText());
            if (!updates.isEmpty())
                conn = updateHosts(conn, url, user, password, hosts, available.path("hash").asText());
        } finally {
            // Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
            pool.setRepositories(conn, previous);
            if (existing == null) repo.forget(conn);
        }
        reportVmGuidance(conn);
        System.out.println("OK: offline-pool-update");
        Session.logout(conn);
    }
}
```
