<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure updates for an air-gapped pool

Switch a pool with no internet access to offline updates: make an update bundle repository the pool's only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it makes available, then tidy up.

Workflow `configure-offline-updates`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Updates/ConfigureOfflineUpdates.cs`](../../csharp/Updates/ConfigureOfflineUpdates.cs)

```csharp
/// <summary>
/// Switch a pool with no internet access to offline updates: make an update bundle repository the pool's
/// only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it makes
/// available, then tidy up.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureOfflineUpdates("https://xenserver", "root", password, "XS9-update.xsbundle");
/// </code>
/// </example>
/// <remarks>
/// A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool needs
/// a repository of the bundle kind (it can have only one: Repository.introduce_bundle refuses a second
/// with BUNDLE_REPOSITORY_ALREADY_EXISTS, so use the existing one), and it must be the pool's only enabled
/// repository. Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a task in
/// the query string: the pool unpacks and checks the bundle, and the task says how that went. GET
/// /updates then lists what the bundle offers each host, and host.apply_updates applies it with the hash
/// in that list (see ApplyUpdate). Without bundlePath this only switches the channel and back.
/// </remarks>
public static void ConfigureOfflineUpdates(string url, string user, string password, string bundlePath = null)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0].opaque_ref;

    // Remember the pool's own repositories, to put them back afterwards.
    var previous = Pool.get_repositories(session, pool);
    var existing = Repository.get_all_records(session)
        .Where(kv => kv.Value.origin == origin.bundle).Select(kv => kv.Key.opaque_ref).FirstOrDefault();
    var repo = existing ?? Repository.introduce_bundle(session, "sdk-example-offline",
        "Updates from uploaded bundles").opaque_ref;
    try
    {
        Pool.set_repositories(session, pool, new() { new XenRef<Repository>(repo) });
        Console.WriteLine("Pool repositories: " + string.Join(", ",
            Pool.get_repositories(session, pool).Select(r => Repository.get_name_label(session, r.opaque_ref))));

        if (!string.IsNullOrEmpty(bundlePath))
        {
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
                    throw new Exception("bundle upload failed: " +
                                        string.Join(", ", Task.get_error_info(session, task)));
            }
            finally
            {
                Task.destroy(session, task);
            }
            Console.WriteLine($"Uploaded {Path.GetFileName(bundlePath)}");

            using (var client = InsecureHttpClient())
            using (var available = JsonDocument.Parse(
                       client.GetStringAsync($"{url}/updates?session_id={session.opaque_ref}").Result))
            {
                var root = available.RootElement;
                var count = root.TryGetProperty("updates", out var updates) ? updates.GetArrayLength() : 0;
                var hash = root.TryGetProperty("hash", out var h) ? h.GetString() : "";
                Console.WriteLine($"Updates in the bundle: {count} (apply them with hash {hash})");
            }
        }
        else
        {
            Console.WriteLine("No bundle given: pass bundle_path to upload one");
        }
    }
    finally
    {
        // Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
        Pool.set_repositories(session, pool, previous);
        if (existing == null) Repository.forget(session, repo);
    }
    Console.WriteLine("OK: configure-offline-updates");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Pool repositories: sdk-example-offline
No bundle given: pass bundle_path to upload one
OK: configure-offline-updates
```

</details>

## Python

Source: [`python/updates/configure_offline_updates.py`](../../python/updates/configure_offline_updates.py)

```python
"""Configure updates for an air-gapped pool.

Switch a pool with no internet access to offline updates: make an update bundle repository the pool's
only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it makes
available, then tidy up.

Run it::

    configure_offline_updates("https://xenserver", "root", password, bundle_path="XS9-update.xsbundle")
"""

import json
import os
import ssl
import time
import urllib.request

from connection import connect


def configure_offline_updates(url, username, password, bundle_path=None):
    """Make a bundle repository the pool's only repository and upload bundle_path (an .xsbundle) to it.

    A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool
    needs a repository of the bundle kind (it can have only one: Repository.introduce_bundle refuses a
    second with BUNDLE_REPOSITORY_ALREADY_EXISTS, so use the existing one), and it must be the pool's
    only enabled repository. Uploading is an HTTP PUT to /bundle alongside the API, with the session id and
    a task in the query string: the pool unpacks and checks the bundle, and the task says how that went.
    GET /updates then lists what the bundle offers each host, and host.apply_updates applies it with
    the hash in that list (see apply-update). Without bundle_path this only switches the channel and
    back."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]
    ctx = ssl._create_unverified_context()

    # Remember the pool's own repositories, to put them back afterwards.
    previous = x.pool.get_repositories(pool)
    existing = [r for r, rec in x.Repository.get_all_records().items() if rec["origin"] == "bundle"]
    repo = existing[0] if existing else x.Repository.introduce_bundle("sdk-example-offline",
                                                                      "Updates from uploaded bundles")
    try:
        x.pool.set_repositories(pool, [repo])
        print("Pool repositories: %s" % ", ".join(x.Repository.get_name_label(r)
                                                  for r in x.pool.get_repositories(pool)))

        if bundle_path:
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
            print("Updates in the bundle: %d (apply them with hash %s)"
                  % (len(available.get("updates", [])), available.get("hash", "")))
        else:
            print("No bundle given: pass bundle_path to upload one")
    finally:
        # Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
        x.pool.set_repositories(pool, previous)
        if not existing:
            x.Repository.forget(repo)
    print("OK: configure-offline-updates")
    session.logout()
```

<details><summary>Example output</summary>

```text
Pool repositories: sdk-example-offline
No bundle given: pass bundle_path to upload one
OK: configure-offline-updates
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/updates/ConfigureOfflineUpdates.java`](../../java/src/main/java/com/xenserver/samples/updates/ConfigureOfflineUpdates.java)

```java
package com.xenserver.samples.updates;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.xensource.xenapi.Connection;
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
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class ConfigureOfflineUpdates {
    private ConfigureOfflineUpdates() {
    }

    /**
     * Configure updates for an air-gapped pool.
     *
     * <p>Switch a pool with no internet access to offline updates: make an update bundle repository the
     * pool's only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it
     * makes available, then tidy up.
     *
     * <p>A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool
     * needs a repository of the bundle kind (it can have only one: Repository.introduce_bundle refuses a
     * second with BUNDLE_REPOSITORY_ALREADY_EXISTS, so use the existing one), and it must be the pool's only
     * enabled repository. Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a
     * task in the query string: the pool unpacks and checks the bundle, and the task says how that went. GET
     * /updates then lists what the bundle offers each host, and host.apply_updates applies it with the hash
     * in that list (see ApplyUpdate). With a null bundlePath this only switches the channel and back.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureOfflineUpdates.run("https://xenserver", "root", password, "XS9-update.xsbundle");
     * }</pre>
     */
    public static void run(String url, String user, String password, String bundlePath) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();

        // Remember the pool's own repositories, to put them back afterwards.
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

            if (bundlePath != null && !bundlePath.isEmpty()) {
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
                        throw new RuntimeException("bundle upload failed: " + task.getErrorInfo(conn));
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
                System.out.printf("Updates in the bundle: %d (apply them with hash %s)%n",
                    available.path("updates").size(), available.path("hash").asText());
            } else {
                System.out.println("No bundle given: pass bundle_path to upload one");
            }
        } finally {
            // Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
            pool.setRepositories(conn, previous);
            if (existing == null) repo.forget(conn);
        }
        System.out.println("OK: configure-offline-updates");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Pool repositories: sdk-example-offline
No bundle given: pass bundle_path to upload one
OK: configure-offline-updates
```

</details>

## Go

Source: [`go/configure_offline_updates.go`](../../go/configure_offline_updates.go)

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

// configureOfflineUpdates - Configure updates for an air-gapped pool.
//
// Switch a pool with no internet access to offline updates: make an update bundle repository the
// pool's only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates
// it makes available, then tidy up.
//
// A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool
// needs a repository of the bundle kind (it can have only one: Repository.introduce_bundle refuses a
// second with BUNDLE_REPOSITORY_ALREADY_EXISTS, so use the existing one), and it must be the pool's only
// enabled repository. Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a
// task in the query string: the pool unpacks and checks the bundle, and the task says how that went.
// GET /updates then lists what the bundle offers each host, and host.apply_updates applies it with the
// hash in that list (see applyUpdate). With an empty bundlePath this only switches the channel and back.
//
// Run it:
//
//	configureOfflineUpdates("https://xenserver", "root", password, "XS9-update.xsbundle")
func configureOfflineUpdates(url, user, password, bundlePath string) {
	session := connect(url, user, password)
	defer session.Logout()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]

	// Remember the pool's own repositories, to put them back afterwards.
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

	if bundlePath == "" {
		fmt.Println("No bundle given: pass bundle_path to upload one")
		fmt.Println("OK: configure-offline-updates")
		return
	}

	// The Go binding keeps its own session id private, so log in once more for the HTTP transfers.
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
		Hash    string            `json:"hash"`
		Updates []json.RawMessage `json:"updates"`
	}
	check(json.NewDecoder(response.Body).Decode(&available))
	fmt.Printf("Updates in the bundle: %d (apply them with hash %s)\n", len(available.Updates), available.Hash)
	fmt.Println("OK: configure-offline-updates")
}
```

<details><summary>Example output</summary>

```text
Pool repositories: sdk-example-offline
No bundle given: pass bundle_path to upload one
OK: configure-offline-updates
```

</details>

## PowerShell

Source: [`powershell/Updates/Invoke-ConfigureOfflineUpdates.ps1`](../../powershell/Updates/Invoke-ConfigureOfflineUpdates.ps1)

```powershell
function Invoke-ConfigureOfflineUpdates {
    <#
    .SYNOPSIS
        Configure updates for an air-gapped pool.
    .DESCRIPTION
        Switch a pool with no internet access to offline updates: make an update bundle repository the pool's
        only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it makes
        available, then tidy up.

        A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool
        needs a repository of the bundle kind (it can have only one: introducing a second fails with
        BUNDLE_REPOSITORY_ALREADY_EXISTS, so use the existing one), and it must be the pool's only enabled
        repository. Send-XenBundle uploads the bundle with a task to report on: the pool unpacks and checks
        it, and the task says how that went. Receive-XenUpdates then lists what the bundle offers each host,
        and Invoke-XenHost -XenAction ApplyUpdates applies it with the hash in that list (see
        Invoke-ApplyUpdate). Without BundlePath this only switches the channel and back.
    .EXAMPLE
        Invoke-ConfigureOfflineUpdates -Url https://xenserver -UserName root -Password $password -BundlePath .\XS9-update.xsbundle
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$BundlePath
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    # Remember the pool's own repositories, to put them back afterwards.
    $previous = @($pool.repositories | ForEach-Object { $_.opaque_ref })
    $existing = Get-XenRepository | Where-Object { $_.origin -eq 'bundle' } | Select-Object -First 1
    $repo = if ($existing) { $existing } else {
        # Repository.introduce_bundle is a static-style create, so pass the NULL ref for the (ignored)
        # instance param.
        Invoke-XenRepository -Ref 'OpaqueRef:NULL' -XenAction IntroduceBundle -NameLabel "sdk-example-offline" `
            -NameDescription "Updates from uploaded bundles" -PassThru
    }
    try {
        $pool | Set-XenPool -Repositories @($repo.opaque_ref)
        Write-Host ("Pool repositories: " + ((Get-XenPool -Ref $pool.opaque_ref).repositories |
            ForEach-Object { (Get-XenRepository -Ref $_.opaque_ref).name_label }) -join ", ")

        if ($BundlePath) {
            $coordinator = Get-XenHost -Ref $pool.master.opaque_ref
            $task = New-XenTask -Label "sdk-example-bundle-upload" -Description "" -PassThru
            Send-XenBundle -XenHost $coordinator.address -Path $BundlePath -TaskRef $task.opaque_ref `
                -NoWarnCertificates -NoWarnNewCertificates
            $task | Wait-XenTask -ShowProgress
            $finished = Get-XenTask -Ref $task.opaque_ref
            Remove-XenTask -Ref $task.opaque_ref
            if ($finished.status -ne 'success') { throw "bundle upload failed: $($finished.error_info -join ' ')" }
            Write-Host "Uploaded $(Split-Path $BundlePath -Leaf)"

            $json = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-updates-$([guid]::NewGuid().Guid).json"
            $task = New-XenTask -Label "sdk-example-updates" -Description "" -PassThru
            Receive-XenUpdates -XenHost $coordinator.address -Path $json -TaskRef $task.opaque_ref `
                -NoWarnCertificates -NoWarnNewCertificates
            $task | Wait-XenTask
            Remove-XenTask -Ref $task.opaque_ref
            $available = Get-Content -Raw -Path $json | ConvertFrom-Json
            Remove-Item $json
            Write-Host "Updates in the bundle: $(@($available.updates).Count) (apply them with hash $($available.hash))"
        }
        else {
            Write-Host "No bundle given: pass bundle_path to upload one"
        }
    }
    finally {
        # Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
        $pool | Set-XenPool -Repositories $previous
        if (-not $existing) { $repo | Invoke-XenRepository -XenAction Forget }
    }
    Write-Host "OK: configure-offline-updates"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Pool repositories: sdk-example-offline
No bundle given: pass bundle_path to upload one
OK: configure-offline-updates
```

</details>

## xe CLI

Source: [`cli/updates/configure-offline-updates.sh`](../../cli/updates/configure-offline-updates.sh)

```bash
# Configure updates for an air-gapped pool.
#
# Switch a pool with no internet access to offline updates: make an update bundle repository the pool's
# only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it makes
# available, then tidy up.
#
# Run it:
#   ./workflows.sh configure-offline-updates https://xenserver root "$password" bundle_path=XS9-update.xsbundle
#
# Optional key=value arguments (default):
#   bundle_path ("")

# A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool needs a
# repository of the bundle kind (it can have only one: introducing a second fails, so use the existing
# one), and it must be the pool's only enabled repository. pool-sync-bundle uploads the bundle to the
# coordinator, which unpacks and checks it; xe waits for that to finish. host-apply-updates then applies it
# (see apply-update). Without bundle_path this only switches the channel and back.
configure_offline_updates() {
    local bundle_path pool before repo existing
    bundle_path=$(param bundle_path "")
    pool=$(xe pool-list --minimal)

    # Remember the pool's own repositories, to put them back afterwards. A set reads back "a; b".
    before=$(xe pool-param-get uuid=$pool param-name=repositories)
    existing=$(xe repository-list origin=bundle --minimal)
    if [ -n "$existing" ]; then
        repo=$(first_csv "$existing")
    else
        repo=$(xe repository-introduce-bundle name-label=sdk-example-offline \
            name-description="Updates from uploaded bundles")
    fi
    xe pool-param-set uuid=$pool repositories=$repo
    echo "Pool repositories: $(xe repository-param-get uuid=$repo param-name=name-label)"

    if [ -n "$bundle_path" ]; then
        xe pool-sync-bundle filename="$bundle_path"
        echo "Uploaded $(basename "$bundle_path")"
    else
        echo "No bundle given: pass bundle_path to upload one"
    fi

    # Forgetting a repository the pool still has enabled fails: restore the pool's own first.
    xe pool-param-set uuid=$pool repositories="$(set_to_csv "$before")"
    [ -n "$existing" ] || xe repository-forget uuid=$repo
    echo "OK: configure-offline-updates"
}
```

<details><summary>Example output</summary>

```text
Pool repositories: sdk-example-offline
No bundle given: pass bundle_path to upload one
OK: configure-offline-updates
```

</details>
