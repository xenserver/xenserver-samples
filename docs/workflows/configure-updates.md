<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure updates (CDN)

Point the pool at a CDN update repository and turn on automatic update sync: register a repository, set it as the pool's repository, enable update sync, read it back, then tidy up.

Workflow `configure-updates`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Updates/Invoke-ConfigureUpdates.ps1`](../../powershell/Updates/Invoke-ConfigureUpdates.ps1)

```powershell
function Invoke-ConfigureUpdates {
    <#
    .SYNOPSIS
        Configure updates (CDN).
    .DESCRIPTION
        Point the pool at a CDN update repository and turn on automatic update sync: register a repository,
        set it as the pool's repository, enable update sync, read it back, then tidy up.
    .EXAMPLE
        Invoke-ConfigureUpdates -Url https://xenserver -UserName root -Password $password `
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
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $repos = @(New-UpdateRepositories -Session $session -RepoUrl $RepoUrl -SourceUrl $SourceUrl)
    Write-Host "Introduced repositories: $(($repos | ForEach-Object { $_.name_label }) -join ', ')"

    $pool = Get-XenPool | Select-Object -First 1
    # Remember the pool's own repositories, to put them back afterwards.
    $previous = @((Get-XenPool -Ref $pool.opaque_ref).repositories | ForEach-Object { $_.opaque_ref })
    $pool | Set-XenPool -Repositories @($repos | ForEach-Object { $_.opaque_ref })
    $pool | Set-XenPool -UpdateSyncEnabled $true
    $p = Get-XenPool -Ref $pool.opaque_ref
    Write-Host "Pool repositories: $($p.repositories.Count); auto-sync enabled: $($p.update_sync_enabled)"

    # Tidy up so the example is repeatable.
    $pool | Set-XenPool -UpdateSyncEnabled $false
    $pool | Set-XenPool -Repositories $previous
    $repos | ForEach-Object { $_ | Invoke-XenRepository -XenAction Forget }
    Write-Host "OK: configure-updates"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Introduced repositories: sdk-example-base, sdk-example-normal
Pool repositories: 2; auto-sync enabled: True
OK: configure-updates
```

</details>

## xe CLI

Source: [`cli/updates/configure-updates.sh`](../../cli/updates/configure-updates.sh)

```bash
# Configure updates (CDN).
#
# Point the pool at a CDN update repository and turn on automatic update sync: register a repository, set it
# as the pool's repository, enable update sync, read it back, then tidy up.
#
# Run it:
#   ./workflows.sh configure-updates https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)

configure_updates() {
    local repo_url source_url repos repo_list names pool before
    repo_url=$(param repo_url "https://repo.ops.xenserver.com/xs9")
    source_url=$(param source_url "https://repo-src.ops.xenserver.com/xs9")
    pool=$(xe pool-list --minimal)
    repos=$(introduce_update_repositories "$repo_url" "$source_url")
    repo_list="" names=""
    for r in $repos; do
        repo_list="${repo_list:+$repo_list,}$r"
        names="${names:+$names, }$(xe repository-param-get uuid=$r param-name=name-label)"
    done
    echo "Introduced repositories: $names"

    # Remember the pool's own repositories, to put them back afterwards. A set reads back "a; b" and is
    # set as "a,b".
    before=$(xe pool-param-get uuid=$pool param-name=repositories)
    xe pool-param-set uuid=$pool repositories=$repo_list
    # The pool's update-sync-enabled is read-only to param-set; xe switches it with its own command.
    xe pool-set-update-sync-enabled value=true
    echo "Pool repositories: $(count_csv "$repo_list"); auto-sync enabled: $(xe pool-param-get uuid=$pool param-name=update-sync-enabled)"

    # Tidy up so the example is repeatable.
    xe pool-set-update-sync-enabled value=false
    xe pool-param-set uuid=$pool repositories="${before//; /,}"
    for r in $repos; do xe repository-forget uuid=$r; done
    echo "OK: configure-updates"
}
```

<details><summary>Example output</summary>

```text
Introduced repositories: sdk-example-base, sdk-example-normal
Pool repositories: 2; auto-sync enabled: true
OK: configure-updates
```

</details>

## Python

Source: [`python/updates/configure_updates.py`](../../python/updates/configure_updates.py)

```python
"""Configure updates (CDN).

Point the pool at a CDN update repository and turn on automatic update sync: register a repository,
set it as the pool's repository, enable update sync, read it back, then tidy up.

Run it::

    configure_updates("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

from connection import connect
from helpers import introduce_update_repositories


def configure_updates(url, username, password, repo_url, source_url):
    """Point the pool at the CDN's repositories and enable automatic update sync."""
    session = connect(url, username, password)
    repos = introduce_update_repositories(session, repo_url, source_url)
    print("Introduced repositories: %s"
          % ", ".join(session.xenapi.Repository.get_name_label(r) for r in repos))

    pool = session.xenapi.pool.get_all()[0]
    # Remember the pool's own repositories, to put them back afterwards.
    previous = session.xenapi.pool.get_repositories(pool)
    session.xenapi.pool.set_repositories(pool, repos)
    session.xenapi.pool.set_update_sync_enabled(pool, True)
    print("Pool repositories: %d; auto-sync enabled: %s"
          % (len(session.xenapi.pool.get_repositories(pool)),
             session.xenapi.pool.get_update_sync_enabled(pool)))

    # Tidy up so the example is repeatable.
    session.xenapi.pool.set_update_sync_enabled(pool, False)
    session.xenapi.pool.set_repositories(pool, previous)
    for repo in repos:
        session.xenapi.Repository.forget(repo)
    print("OK: configure-updates")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Introduced repositories: sdk-example-base, sdk-example-normal
Pool repositories: 2; auto-sync enabled: True
OK: configure-updates
```

</details>

## C# (.NET)

Source: [`csharp/Updates/ConfigureUpdates.cs`](../../csharp/Updates/ConfigureUpdates.cs)

```csharp
/// <summary>
/// Point the pool at a CDN update repository and turn on automatic update sync: register a repository,
/// set it as the pool's repository, enable update sync, read it back, then tidy up.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureUpdates("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
/// Workflows."https://repo-src.ops.xenserver.com/xs9");
/// </code>
/// </example>
public static void ConfigureUpdates(string url, string user, string password, string repoUrl, string sourceUrl)
{
    var session = Connect(url, user, password);
    var repos = IntroduceUpdateRepositories(session, repoUrl, sourceUrl);
    Console.WriteLine("Introduced repositories: " +
        string.Join(", ", repos.Select(r => Repository.get_name_label(session, r.opaque_ref))));

    var pool = Pool.get_all(session)[0].opaque_ref;
    // Remember the pool's own repositories, to put them back afterwards.
    var previous = Pool.get_repositories(session, pool);
    Pool.set_repositories(session, pool, repos);
    Pool.set_update_sync_enabled(session, pool, true);
    Console.WriteLine($"Pool repositories: {Pool.get_repositories(session, pool).Count}; " +
        $"auto-sync enabled: {Pool.get_update_sync_enabled(session, pool)}");

    // Tidy up so the example is repeatable.
    Pool.set_update_sync_enabled(session, pool, false);
    Pool.set_repositories(session, pool, previous);
    foreach (var repo in repos) Repository.forget(session, repo.opaque_ref);
    Console.WriteLine("OK: configure-updates");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Introduced repositories: sdk-example-base, sdk-example-normal
Pool repositories: 2; auto-sync enabled: True
OK: configure-updates
```

</details>

## Go

Source: [`go/configure_updates.go`](../../go/configure_updates.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// configureUpdates - Configure updates (CDN).
//
// Point the pool at a CDN update repository and turn on automatic update sync: register a
// repository, set it as the pool's repository, enable update sync, read it back, then tidy up.
//
// Run it:
//
//	configureUpdates("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
//	"https://repo-src.ops.xenserver.com/xs9")
func configureUpdates(url, user, password, repoURL, sourceURL string) {
	session := connect(url, user, password)
	repos := introduceUpdateRepositories(session, repoURL, sourceURL)
	var names []string
	for _, repo := range repos {
		name, _ := xenapi.Repository.GetNameLabel(session, repo)
		names = append(names, name)
	}
	fmt.Printf("Introduced repositories: %s\n", strings.Join(names, ", "))

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	// Remember the pool's own repositories, to put them back afterwards.
	previous, perr := xenapi.Pool.GetRepositories(session, pool)
	check(perr)
	check(xenapi.Pool.SetRepositories(session, pool, repos))
	check(xenapi.Pool.SetUpdateSyncEnabled(session, pool, true))
	nowRepos, _ := xenapi.Pool.GetRepositories(session, pool)
	enabled, _ := xenapi.Pool.GetUpdateSyncEnabled(session, pool)
	fmt.Printf("Pool repositories: %d; auto-sync enabled: %v\n", len(nowRepos), enabled)

	// Tidy up so the example is repeatable.
	check(xenapi.Pool.SetUpdateSyncEnabled(session, pool, false))
	check(xenapi.Pool.SetRepositories(session, pool, previous))
	for _, repo := range repos {
		check(xenapi.Repository.Forget(session, repo))
	}
	fmt.Println("OK: configure-updates")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Introduced repositories: sdk-example-base, sdk-example-normal
Pool repositories: 2; auto-sync enabled: true
OK: configure-updates
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/updates/ConfigureUpdates.java`](../../java/src/main/java/com/xenserver/samples/updates/ConfigureUpdates.java)

```java
package com.xenserver.samples.updates;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Repository;
import com.xensource.xenapi.Session;

import java.util.Set;

import static com.xenserver.samples.Helpers.introduceUpdateRepositories;
import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureUpdates {
    private ConfigureUpdates() {
    }

    /**
     * Configure updates (CDN).
     *
     * <p>Point the pool at a CDN update repository and turn on automatic update sync: register a
     * repository, set it as the pool's repository, enable update sync, read it back, then tidy up.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureUpdates.run("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
     * "https://repo-src.ops.xenserver.com/xs9");
     * }</pre>
     */
    public static void run(String url, String user, String password, String repoUrl,
            String sourceUrl) throws Exception {
        Connection conn = connect(url, user, password);
        Set<Repository> repos = introduceUpdateRepositories(conn, repoUrl, sourceUrl);
        StringBuilder names = new StringBuilder();
        for (Repository repo : repos) {
            if (names.length() > 0) names.append(", ");
            names.append(repo.getNameLabel(conn));
        }
        System.out.println("Introduced repositories: " + names);

        Pool pool = Pool.getAll(conn).iterator().next();
        // Remember the pool's own repositories, to put them back afterwards.
        Set<Repository> previous = pool.getRepositories(conn);
        pool.setRepositories(conn, repos);
        pool.setUpdateSyncEnabled(conn, true);
        System.out.println("Pool repositories: " + pool.getRepositories(conn).size()
                + "; auto-sync enabled: " + pool.getUpdateSyncEnabled(conn));

        // Tidy up so the example is repeatable.
        pool.setUpdateSyncEnabled(conn, false);
        pool.setRepositories(conn, previous);
        for (Repository repo : repos) repo.forget(conn);
        System.out.println("OK: configure-updates");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Introduced repositories: sdk-example-base, sdk-example-normal
Pool repositories: 2; auto-sync enabled: true
OK: configure-updates
```

</details>
