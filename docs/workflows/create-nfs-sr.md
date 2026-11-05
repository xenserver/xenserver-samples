<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create an NFS SR

Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and forget it.

Workflow `create-nfs-sr`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Storage/CreateNfsSr.cs`](../../csharp/Storage/CreateNfsSr.cs)

```csharp
/// <summary>
/// Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and forget
/// it.
/// </summary>
/// <example>
/// <code>
/// Workflows.CreateNfsSr("https://xenserver", "root", password, "192.0.2.10", "/export/sdk");
/// </code>
/// </example>
public static void CreateNfsSr(string url, string user, string password,
    string nfsServer, string nfsPath, string srName = "sdk-example-nfs")
{
    var session = Connect(url, user, password);
    var hostRef = Host.get_all_records(session).Keys.First().opaque_ref;
    var deviceConfig = new Dictionary<string, string>
    {
        ["server"] = nfsServer,
        ["serverpath"] = nfsPath,
        ["nfsversion"] = "3",
    };

    var srRef = SR.create(session, hostRef, deviceConfig, 0,
        srName, "NFS SR created by the SDK example",
        "nfs", "user", true, new Dictionary<string, string>());
    Console.WriteLine($"Created SR: {SR.get_uuid(session, srRef.opaque_ref)}");

    DetachAndForgetSr(session, srRef.opaque_ref);
    Console.WriteLine("OK: create-nfs-sr");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Created SR: 00000001-0000-0000-a90a-000000000000
OK: create-nfs-sr
```

</details>

## Python

Source: [`python/storage/create_nfs_sr.py`](../../python/storage/create_nfs_sr.py)

```python
"""Create an NFS SR.

Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and
forget it.

Run it::

    create_nfs_sr("https://xenserver", "root", password, "192.0.2.10", "/export/sdk")
"""

from connection import connect
from helpers import detach_and_forget_sr


def create_nfs_sr(url, username, password, nfs_server, nfs_path, sr_name="sdk-example-nfs"):
    """Create a shared NFS SR (as the New SR wizard does), then forget it."""
    session = connect(url, username, password)
    host_ref = next(iter(session.xenapi.host.get_all_records().keys()))
    device_config = {"server": nfs_server, "serverpath": nfs_path, "nfsversion": "3"}

    sr_ref = session.xenapi.SR.create(
        host_ref, device_config, "0",
        sr_name, "NFS SR created by the SDK example",
        "nfs", "user", True, {})
    print("Created SR: %s" % session.xenapi.SR.get_uuid(sr_ref))

    detach_and_forget_sr(session, sr_ref)
    print("OK: create-nfs-sr")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Created SR: 00000001-0000-0000-bb0a-000000000000
OK: create-nfs-sr
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/CreateNfsSr.java`](../../java/src/main/java/com/xenserver/samples/storage/CreateNfsSr.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.Helpers.detachAndForgetSr;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateNfsSr {
    private CreateNfsSr() {
    }

    /**
     * Create an NFS SR.
     *
     * <p>Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and
     * forget it.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateNfsSr.run("https://xenserver", "root", password, "192.0.2.10", "/export/sdk", "sdk-example-nfs");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String nfsServer, String nfsPath, String srName) throws Exception {
        Connection conn = connect(url, user, password);
        Host host = Host.getAllRecords(conn).keySet().iterator().next();
        Map<String, String> deviceConfig = new java.util.HashMap<>();
        deviceConfig.put("server", nfsServer);
        deviceConfig.put("serverpath", nfsPath);
        deviceConfig.put("nfsversion", "3");

        SR sr = SR.create(conn, host, deviceConfig, 0L,
            srName, "NFS SR created by the SDK example",
            "nfs", "user", true, new java.util.HashMap<>());
        System.out.println("Created SR: " + sr.getUuid(conn));

        detachAndForgetSr(conn, sr);
        System.out.println("OK: create-nfs-sr");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
Created SR: 00000001-0000-0000-ac0a-000000000000
OK: create-nfs-sr
```

</details>

## Go

Source: [`go/create_nfs_sr.go`](../../go/create_nfs_sr.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// createNfsSR - Create an NFS SR.
//
// Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and
// forget it.
//
// Run it:
//
//	createNfsSR("https://xenserver", "root", password, "192.0.2.10", "/export/sdk", "sdk-example-nfs")
func createNfsSR(url, user, password, nfsServer, nfsPath, srName string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var hostRef xenapi.HostRef
	for ref := range hosts {
		hostRef = ref
		break
	}

	deviceConfig := map[string]string{
		"server":     nfsServer,
		"serverpath": nfsPath,
		"nfsversion": "3",
	}
	srRef, err := xenapi.SR.Create(session, hostRef, deviceConfig, 0,
		srName, "NFS SR created by the SDK example",
		"nfs", "user", true, map[string]string{})
	check(err)
	uuid, _ := xenapi.SR.GetUUID(session, srRef)
	fmt.Printf("Created SR: %s\n", uuid)

	detachAndForgetSR(session, srRef)
	fmt.Println("OK: create-nfs-sr")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Created SR: 00000001-0000-0000-4b0a-000000000000
OK: create-nfs-sr
```

</details>

## PowerShell

Source: [`powershell/Storage/Invoke-CreateNfsSr.ps1`](../../powershell/Storage/Invoke-CreateNfsSr.ps1)

```powershell
function Invoke-CreateNfsSr {
    <#
    .SYNOPSIS
        Create an NFS SR.
    .DESCRIPTION
        Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and
        forget it.
    .EXAMPLE
        Invoke-CreateNfsSr -Url https://xenserver -UserName root -Password $password -NfsServer 192.0.2.10 -NfsPath /export/sdk
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$NfsServer,
        [Parameter(Mandatory = $true)][string]$NfsPath,
        [string]$SrName = "sdk-example-nfs"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $deviceConfig = @{ server = $NfsServer; serverpath = $NfsPath; nfsversion = "3" }

    $sr = New-XenSR -XenHost $xenHost -DeviceConfig $deviceConfig -PhysicalSize 0 `
        -NameLabel $SrName -NameDescription "NFS SR created by the SDK example" `
        -Type "nfs" -ContentType "user" -Shared $true -PassThru
    Write-Host "Created SR: $($sr.uuid)"

    Invoke-DetachAndForgetSr -Ref $sr.opaque_ref
    Write-Host "OK: create-nfs-sr"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Created SR: 00000001-0000-0000-d80a-000000000000
OK: create-nfs-sr
```

</details>

## xe CLI

Source: [`cli/storage/create-nfs-sr.sh`](../../cli/storage/create-nfs-sr.sh)

```bash
# Create an NFS SR.
#
# Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and forget it.
#
# Run it:
#   ./workflows.sh create-nfs-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   nfs_server (192.0.2.10)
#   nfs_path (/export/sdk)

create_nfs_sr() {
    local nfs_server nfs_path
    nfs_server=$(param nfs_server "192.0.2.10")
    nfs_path=$(param nfs_path "/export/sdk")
    sr=$(xe sr-create host-uuid=$(first_host) type=nfs name-label=xe-example-nfs \
        device-config:server="$nfs_server" device-config:serverpath="$nfs_path" device-config:nfsversion=3 shared=true)
    echo "Created SR: $sr"
    detach_and_forget_sr $sr
    echo "OK: create-nfs-sr"
}
```

<details><summary>Sample output</summary>

```text
Created SR: 00000001-0000-0000-8a0a-000000000000
OK: create-nfs-sr
```

</details>
