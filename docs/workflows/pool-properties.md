<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Pool properties

Read the pool name and default storage repository, then rename the pool and restore it.

Workflow `pool-properties`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-PoolProperties.ps1`](../../powershell/HostsAndPools/Invoke-PoolProperties.ps1)

```powershell
function Invoke-PoolProperties {
    <#
    .SYNOPSIS
        Pool properties.
    .DESCRIPTION
        Read the pool name and default storage repository, then rename the pool and restore it.
    .EXAMPLE
        Invoke-PoolProperties -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    $original = $pool.name_label
    $defaultSr = $pool.default_SR.opaque_ref
    $srName = if ($defaultSr -eq "OpaqueRef:NULL") { "(none)" } else { (Get-XenSR -Ref $defaultSr).name_label }
    Write-Host "Pool:       '$original'"
    Write-Host "Default SR: $srName"

    $pool | Set-XenPool -NameLabel "sdk-pool-renamed"
    Write-Host "Renamed to: '$((Get-XenPool -Ref $pool.opaque_ref).name_label)'"

    $pool | Set-XenPool -NameLabel $original  # restore
    Write-Host "OK: pool-properties"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Pool:       'sdk-pool'
Default SR: Shared NFS
Renamed to: 'sdk-pool-renamed'
OK: pool-properties
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/pool-properties.sh`](../../cli/hosts-and-pools/pool-properties.sh)

```bash
# Pool properties.
#
# Read the pool name and default storage repository, then rename the pool and restore it.
#
# Run it:
#   ./workflows.sh pool-properties https://xenserver root "$password"

pool_properties() {
    pool=$(xe pool-list --minimal)
    original=$(xe pool-param-get uuid=$pool param-name=name-label)
    echo "Pool: '$original'"
    xe pool-param-set uuid=$pool name-label=xe-pool-renamed
    echo "Renamed to: '$(xe pool-param-get uuid=$pool param-name=name-label)'"
    xe pool-param-set uuid=$pool name-label="$original"
    echo "OK: pool-properties"
}
```

<details><summary>Example output</summary>

```text
Pool: 'sdk-pool'
Renamed to: 'xe-pool-renamed'
OK: pool-properties
```

</details>

## Python

Source: [`python/hosts_and_pools/pool_properties.py`](../../python/hosts_and_pools/pool_properties.py)

```python
"""Pool properties.

Read the pool name and default storage repository, then rename the pool and restore it.

Run it::

    pool_properties("https://xenserver", "root", password)
"""

from connection import connect


def pool_properties(url, username, password):
    """Read the pool's name and default SR, rename the pool, then restore the name."""
    session = connect(url, username, password)
    pool_ref = session.xenapi.pool.get_all()[0]
    original = session.xenapi.pool.get_name_label(pool_ref)
    default_sr = session.xenapi.pool.get_default_SR(pool_ref)
    print("Pool:       '%s'" % original)
    print("Default SR: %s"
          % ("(none)" if default_sr == "OpaqueRef:NULL"
             else session.xenapi.SR.get_name_label(default_sr)))

    session.xenapi.pool.set_name_label(pool_ref, "sdk-pool-renamed")
    print("Renamed to: '%s'" % session.xenapi.pool.get_name_label(pool_ref))
    session.xenapi.pool.set_name_label(pool_ref, original)  # restore
    print("OK: pool-properties")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Pool:       'sdk-pool'
Default SR: Shared NFS
Renamed to: 'sdk-pool-renamed'
OK: pool-properties
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/PoolProperties.cs`](../../csharp/HostsAndPools/PoolProperties.cs)

```csharp
/// <summary>
/// Read the pool name and default storage repository, then rename the pool and restore it.
/// </summary>
/// <example>
/// <code>
/// Workflows.PoolProperties("https://xenserver", "root", password);
/// </code>
/// </example>
public static void PoolProperties(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var poolRef = Pool.get_all(session)[0].opaque_ref;
    var original = Pool.get_name_label(session, poolRef);
    var defaultSr = Pool.get_default_SR(session, poolRef).opaque_ref;
    Console.WriteLine($"Pool:       '{original}'");
    Console.WriteLine($"Default SR: {(defaultSr == "OpaqueRef:NULL" ? "(none)" : SR.get_name_label(session, defaultSr))}");

    Pool.set_name_label(session, poolRef, "sdk-pool-renamed");
    Console.WriteLine($"Renamed to: '{Pool.get_name_label(session, poolRef)}'");
    Pool.set_name_label(session, poolRef, original); // restore
    Console.WriteLine("OK: pool-properties");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Pool:       'sdk-pool'
Default SR: Shared NFS
Renamed to: 'sdk-pool-renamed'
OK: pool-properties
```

</details>

## Go

Source: [`go/pool_properties.go`](../../go/pool_properties.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// poolProperties - Pool properties.
//
// Read the pool name and default storage repository, then rename the pool and restore it.
//
// Run it:
//
//	poolProperties("https://xenserver", "root", password)
func poolProperties(url, user, password string) {
	session := connect(url, user, password)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	poolRef := pools[0]
	original, _ := xenapi.Pool.GetNameLabel(session, poolRef)
	defaultSr, _ := xenapi.Pool.GetDefaultSR(session, poolRef)
	srName := "(none)"
	if defaultSr != xenapi.SRRef("OpaqueRef:NULL") {
		srName, _ = xenapi.SR.GetNameLabel(session, defaultSr)
	}
	fmt.Printf("Pool:       '%s'\n", original)
	fmt.Printf("Default SR: %s\n", srName)

	check(xenapi.Pool.SetNameLabel(session, poolRef, "sdk-pool-renamed"))
	now, _ := xenapi.Pool.GetNameLabel(session, poolRef)
	fmt.Printf("Renamed to: '%s'\n", now)
	check(xenapi.Pool.SetNameLabel(session, poolRef, original)) // restore
	fmt.Println("OK: pool-properties")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Pool:       'sdk-pool'
Default SR: Shared NFS
Renamed to: 'sdk-pool-renamed'
OK: pool-properties
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/PoolProperties.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/PoolProperties.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class PoolProperties {
    private PoolProperties() {
    }

    /**
     * Pool properties.
     *
     * <p>Read the pool name and default storage repository, then rename the pool and restore it.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * PoolProperties.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        String original = pool.getNameLabel(conn);
        SR defaultSr = pool.getDefaultSR(conn);
        System.out.println("Pool:       '" + original + "'");
        System.out.println("Default SR: " + (defaultSr.toWireString().equals("OpaqueRef:NULL")
                ? "(none)" : defaultSr.getNameLabel(conn)));

        pool.setNameLabel(conn, "sdk-pool-renamed");
        System.out.println("Renamed to: '" + pool.getNameLabel(conn) + "'");
        pool.setNameLabel(conn, original); // restore
        System.out.println("OK: pool-properties");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Pool:       'sdk-pool'
Default SR: Shared NFS
Renamed to: 'sdk-pool-renamed'
OK: pool-properties
```

</details>
