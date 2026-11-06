<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create an ISO library SR

Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so the images are available as installation media.

Workflow `create-iso-sr`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Storage/Invoke-CreateIsoSr.ps1`](../../powershell/Storage/Invoke-CreateIsoSr.ps1)

```powershell
function Invoke-CreateIsoSr {
    <#
    .SYNOPSIS
        Create an ISO library SR.
    .DESCRIPTION
        Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so the
        images are available as installation media.

        Connect an ISO-library SR to a file share of ISO images (here an NFS export, Location
        "server:/path").
    .EXAMPLE
        Invoke-CreateIsoSr -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Location
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $deviceConfig = @{ location = $Location; type = "nfs_iso" }
    $sr = New-XenSR -XenHost $xenHost -DeviceConfig $deviceConfig -PhysicalSize 0 `
        -NameLabel "sdk-example-iso" -NameDescription "ISO library created by the SDK example" `
        -Type "iso" -ContentType "iso" -Shared $true -PassThru
    Write-Host "Created ISO SR: $($sr.uuid)"
    Invoke-DetachAndForgetSr -Ref $sr
    Write-Host "OK: create-iso-sr"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Created ISO SR: 00000001-0000-0000-e50a-000000000000
OK: create-iso-sr
```

</details>

## xe CLI

Source: [`cli/storage/create-iso-sr.sh`](../../cli/storage/create-iso-sr.sh)

```bash
# Create an ISO library SR.
#
# Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so the images
# are available as installation media.
#
# Run it:
#   ./workflows.sh create-iso-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   location (192.0.2.10:/isos)

create_iso_sr() {
    # Connect an ISO-library SR to a file share of ISO images (here an NFS export, location
    # "server:/path").
    local location
    location=$(param location "192.0.2.10:/isos")
    sr=$(xe sr-create host-uuid=$(first_host) type=iso name-label=xe-example-iso content-type=iso \
        device-config:location="$location" device-config:type=nfs_iso shared=true)
    echo "Created ISO SR: $sr"
    detach_and_forget_sr $sr
    echo "OK: create-iso-sr"
}
```

<details><summary>Example output</summary>

```text
Created ISO SR: 00000001-0000-0000-e00a-000000000000
OK: create-iso-sr
```

</details>

## Python

Source: [`python/storage/create_iso_sr.py`](../../python/storage/create_iso_sr.py)

```python
"""Create an ISO library SR.

Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so the
images are available as installation media.
"""

from connection import connect
from helpers import detach_and_forget_sr


def create_iso_sr(url, username, password, location):
    """Connect an ISO-library SR to a file share of ISO images (here an NFS export, location
    "server:/path")."""
    session = connect(url, username, password)
    host = session.xenapi.host.get_all()[0]
    dc = {"location": location, "type": "nfs_iso"}
    sr = session.xenapi.SR.create(host, dc, "0", "sdk-example-iso",
                                  "ISO library created by the SDK example", "iso", "iso", True, {})
    print("Created ISO SR: %s" % session.xenapi.SR.get_uuid(sr))
    detach_and_forget_sr(session, sr)
    print("OK: create-iso-sr")
    session.logout()
```

<details><summary>Example output</summary>

```text
Created ISO SR: 00000001-0000-0000-dd0a-000000000000
OK: create-iso-sr
```

</details>

## C# (.NET)

Source: [`csharp/Storage/CreateIsoSr.cs`](../../csharp/Storage/CreateIsoSr.cs)

```csharp
/// <summary>
/// Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so the
/// images are available as installation media.
/// </summary>
/// <example>
/// <code>
/// Workflows.CreateIsoSr("https://xenserver", "root", password, "192.0.2.10:/isos");
/// </code>
/// </example>
/// <remarks>
/// Connect an ISO-library SR to a file share of ISO images (here an NFS export, location "server:/path").
/// </remarks>
public static void CreateIsoSr(string url, string user, string password, string location)
{
    var session = Connect(url, user, password);
    var host = Host.get_all(session)[0];
    var dc = new Dictionary<string, string> { ["location"] = location, ["type"] = "nfs_iso" };
    var sr = SR.create(session, host, dc, 0, "sdk-example-iso", "ISO library created by the SDK example",
        "iso", "iso", true, new Dictionary<string, string>());
    Console.WriteLine($"Created ISO SR: {SR.get_uuid(session, sr)}");
    DetachAndForgetSr(session, sr);
    Console.WriteLine("OK: create-iso-sr");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Created ISO SR: 00000001-0000-0000-080b-000000000000
OK: create-iso-sr
```

</details>

## Go

Source: [`go/create_iso_sr.go`](../../go/create_iso_sr.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// createIsoSr - Create an ISO library SR.
//
// Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so
// the images are available as installation media.
//
// Connect an ISO-library SR to a file share of ISO images (here an NFS export, location
// "server:/path").
func createIsoSr(url, user, password, location string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	dc := map[string]string{"location": location, "type": "nfs_iso"}
	sr, err := xenapi.SR.Create(session, hosts[0], dc, 0, "sdk-example-iso",
		"ISO library created by the SDK example", "iso", "iso", true, map[string]string{})
	check(err)
	uuid, _ := xenapi.SR.GetUUID(session, sr)
	fmt.Printf("Created ISO SR: %s\n", uuid)
	detachAndForgetSR(session, sr)
	fmt.Println("OK: create-iso-sr")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Created ISO SR: 00000001-0000-0000-030b-000000000000
OK: create-iso-sr
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/CreateIsoSr.java`](../../java/src/main/java/com/xenserver/samples/storage/CreateIsoSr.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.Helpers.detachAndForgetSr;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateIsoSr {
    private CreateIsoSr() {
    }

    /**
     * Create an ISO library SR.
     *
     * <p>Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so
     * the images are available as installation media.
     *
     * <p>Connect an ISO-library SR to a file share of ISO images (here an NFS export, location
     * "server:/path").
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateIsoSr.run("https://xenserver", "root", password, "192.0.2.10:/isos");
     * }</pre>
     */
    public static void run(String url, String user, String password, String location) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Host host = Host.getAllRecords(conn).keySet().iterator().next();
            Map<String, String> dc = new java.util.HashMap<>();
            dc.put("location", location);
            dc.put("type", "nfs_iso");
            SR sr = SR.create(conn, host, dc, 0L, "sdk-example-iso", "ISO library created by the SDK example",
                "iso", "iso", true, new java.util.HashMap<>());
            System.out.println("Created ISO SR: " + sr.getUuid(conn));
            detachAndForgetSr(conn, sr);
            System.out.println("OK: create-iso-sr");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
Created ISO SR: 00000001-0000-0000-540a-000000000000
OK: create-iso-sr
```

</details>
