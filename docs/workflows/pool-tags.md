<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Tag the pool

Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and hosts.

Workflow `pool-tags`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Organization/Invoke-PoolTags.ps1`](../../powershell/Organization/Invoke-PoolTags.ps1)

```powershell
function Invoke-PoolTags {
    <#
    .SYNOPSIS
        Tag the pool.
    .DESCRIPTION
        Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and
        hosts.
    .EXAMPLE
        Invoke-PoolTags -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Add-XenPool -Tags appends a tag; the pool's current tags are just its .tags property; and
    # Remove-XenPoolProperty -Tags drops one again.
    $pool = Get-XenPool | Select-Object -First 1
    $pool | Add-XenPool -Tags "sdk-managed"
    Write-Host "Pool tags: $((Get-XenPool -Ref $pool.opaque_ref).tags -join ', ')"
    $pool | Remove-XenPoolProperty -Tags "sdk-managed"
    Write-Host "OK: pool-tags"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Pool tags: sdk-managed
OK: pool-tags
```

</details>

## xe CLI

Source: [`cli/organization/pool-tags.sh`](../../cli/organization/pool-tags.sh)

```bash
# Tag the pool.
#
# Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and hosts.
#
# Run it:
#   ./workflows.sh pool-tags https://xenserver root "$password"

pool_tags() {
    pool=$(xe pool-list --minimal)
    xe pool-param-add uuid=$pool param-name=tags param-key=sdk-managed
    echo "Pool tags: $(xe pool-param-get uuid=$pool param-name=tags)"
    xe pool-param-remove uuid=$pool param-name=tags param-key=sdk-managed
    echo "OK: pool-tags"
}
```

<details><summary>Example output</summary>

```text
Pool tags: sdk-managed
OK: pool-tags
```

</details>

## Python

Source: [`python/organization/pool_tags.py`](../../python/organization/pool_tags.py)

```python
"""Tag the pool.

Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and
hosts.

Run it::

    pool_tags("https://xenserver", "root", password)
"""

from connection import connect


def pool_tags(url, username, password):
    """Add a tag to the pool, read it back, then remove it so the example is repeatable."""
    session = connect(url, username, password)
    pool_ref = session.xenapi.pool.get_all()[0]
    session.xenapi.pool.add_tags(pool_ref, "sdk-managed")
    print("Pool tags: %s" % ", ".join(session.xenapi.pool.get_tags(pool_ref)))
    session.xenapi.pool.remove_tags(pool_ref, "sdk-managed")
    print("OK: pool-tags")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Pool tags: sdk-managed
OK: pool-tags
```

</details>

## C# (.NET)

Source: [`csharp/Organization/PoolTags.cs`](../../csharp/Organization/PoolTags.cs)

```csharp
/// <summary>
/// Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and hosts.
/// </summary>
/// <example>
/// <code>
/// Workflows.PoolTags("https://xenserver", "root", password);
/// </code>
/// </example>
public static void PoolTags(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var poolRef = Pool.get_all(session)[0].opaque_ref;
    Pool.add_tags(session, poolRef, "sdk-managed");
    Console.WriteLine($"Pool tags: {string.Join(", ", Pool.get_tags(session, poolRef))}");
    Pool.remove_tags(session, poolRef, "sdk-managed");
    Console.WriteLine("OK: pool-tags");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Pool tags: sdk-managed
OK: pool-tags
```

</details>

## Go

Source: [`go/pool_tags.go`](../../go/pool_tags.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// poolTags - Tag the pool.
//
// Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and
// hosts.
//
// Run it:
//
//	poolTags("https://xenserver", "root", password)
func poolTags(url, user, password string) {
	session := connect(url, user, password)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	poolRef := pools[0]
	check(xenapi.Pool.AddTags(session, poolRef, "sdk-managed"))
	tags, _ := xenapi.Pool.GetTags(session, poolRef)
	fmt.Printf("Pool tags: %s\n", strings.Join(tags, ", "))
	check(xenapi.Pool.RemoveTags(session, poolRef, "sdk-managed"))
	fmt.Println("OK: pool-tags")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Pool tags: sdk-managed
OK: pool-tags
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/organization/PoolTags.java`](../../java/src/main/java/com/xenserver/samples/organization/PoolTags.java)

```java
package com.xenserver.samples.organization;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class PoolTags {
    private PoolTags() {
    }

    /**
     * Tag the pool.
     *
     * <p>Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and
     * hosts.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * PoolTags.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        pool.addTags(conn, "sdk-managed");
        System.out.println("Pool tags: " + String.join(", ", pool.getTags(conn)));
        pool.removeTags(conn, "sdk-managed");
        System.out.println("OK: pool-tags");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Pool tags: sdk-managed
OK: pool-tags
```

</details>
