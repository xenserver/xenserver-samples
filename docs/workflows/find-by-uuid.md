<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Look up an object by UUID

Resolve a stable UUID back to a live object reference — how to persist a reference to an object across sessions.

Workflow `find-by-uuid`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/GettingStarted/Invoke-FindByUuid.ps1`](../../powershell/GettingStarted/Invoke-FindByUuid.ps1)

```powershell
function Invoke-FindByUuid {
    <#
    .SYNOPSIS
        Look up an object by UUID.
    .DESCRIPTION
        Resolve a stable UUID back to a live object reference — how to persist a reference to an object
        across sessions.
    .EXAMPLE
        Invoke-FindByUuid -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # UUIDs are stable identifiers you can persist and resolve back to a (session-scoped) ref.
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $uuid = $vm.uuid

    $resolved = Get-XenVM -Uuid $uuid
    Write-Host "UUID $uuid resolves to $($resolved.name_label)"
    Write-Host "Same object: $($resolved.uuid -eq $vm.uuid)"
    Write-Host "OK: find-by-uuid"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
UUID 00000001-0000-0000-8d00-000000000000 resolves to web-01
Same object: True
OK: find-by-uuid
```

</details>

## xe CLI

Source: [`cli/getting-started/find-by-uuid.sh`](../../cli/getting-started/find-by-uuid.sh)

```bash
# Look up an object by UUID.
#
# Resolve a stable UUID back to a live object reference — how to persist a reference to an object across
# sessions.
#
# Run it:
#   ./workflows.sh find-by-uuid https://xenserver root "$password"

find_by_uuid() {
    vm=$(vm_uuid web-01)
    echo "UUID $vm resolves to $(xe vm-param-get uuid=$vm param-name=name-label)"
    echo "OK: find-by-uuid"
}
```

<details><summary>Example output</summary>

```text
UUID 00000001-0000-0000-8d00-000000000000 resolves to web-01
OK: find-by-uuid
```

</details>

## Python

Source: [`python/getting_started/find_by_uuid.py`](../../python/getting_started/find_by_uuid.py)

```python
"""Look up an object by UUID.

Resolve a stable UUID back to a live object reference — how to persist a reference to an object
across sessions.

Run it::

    find_by_uuid("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def find_by_uuid(url, username, password, vm_name):
    """Resolve a VM's UUID back to a (session-scoped) ref, as persisted identifiers do."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    uuid = session.xenapi.VM.get_uuid(vm)
    resolved = session.xenapi.VM.get_by_uuid(uuid)
    print("UUID %s resolves to %s" % (uuid, session.xenapi.VM.get_name_label(resolved)))
    print("Same object: %s" % (resolved == vm))
    print("OK: find-by-uuid")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
UUID 00000001-0000-0000-8d00-000000000000 resolves to web-01
Same object: True
OK: find-by-uuid
```

</details>

## C# (.NET)

Source: [`csharp/GettingStarted/FindByUuid.cs`](../../csharp/GettingStarted/FindByUuid.cs)

```csharp
/// <summary>
/// Resolve a stable UUID back to a live object reference — how to persist a reference to an object across
/// sessions.
/// </summary>
/// <example>
/// <code>
/// Workflows.FindByUuid("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void FindByUuid(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);
    // UUIDs are stable identifiers you can persist and resolve back to a (session-scoped) ref.
    var vm = VmByName(session, vmName);
    var uuid = VM.get_uuid(session, vm);
    var resolved = VM.get_by_uuid(session, uuid);
    Console.WriteLine($"UUID {uuid} resolves to {VM.get_name_label(session, resolved)}");
    Console.WriteLine($"Same object: {resolved.Equals(vm)}");
    Console.WriteLine("OK: find-by-uuid");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
UUID 00000001-0000-0000-8d00-000000000000 resolves to web-01
Same object: True
OK: find-by-uuid
```

</details>

## Go

Source: [`go/find_by_uuid.go`](../../go/find_by_uuid.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// findByUUID - Look up an object by UUID.
//
// Resolve a stable UUID back to a live object reference — how to persist a reference to an object
// across sessions.
func findByUUID(url, user, password, vmName string) {
	session := connect(url, user, password)
	// UUIDs are stable identifiers you can persist and resolve back to a (session-scoped) ref.
	vm := vmByName(session, vmName)
	uuid, _ := xenapi.VM.GetUUID(session, vm)
	resolved, err := xenapi.VM.GetByUUID(session, uuid)
	check(err)
	name, _ := xenapi.VM.GetNameLabel(session, resolved)
	fmt.Printf("UUID %s resolves to %s\n", uuid, name)
	fmt.Printf("Same object: %v\n", resolved == vm)
	fmt.Println("OK: find-by-uuid")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
UUID 00000001-0000-0000-8d00-000000000000 resolves to web-01
Same object: true
OK: find-by-uuid
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/gettingstarted/FindByUuid.java`](../../java/src/main/java/com/xenserver/samples/gettingstarted/FindByUuid.java)

```java
package com.xenserver.samples.gettingstarted;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class FindByUuid {
    private FindByUuid() {
    }

    /**
     * Look up an object by UUID.
     *
     * <p>Resolve a stable UUID back to a live object reference — how to persist a reference to an object
     * across sessions.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * FindByUuid.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        // UUIDs are stable identifiers you can persist and resolve back to a (session-scoped) ref.
        VM vm = vmByName(conn, vmName);
        String uuid = vm.getUuid(conn);
        VM resolved = VM.getByUuid(conn, uuid);
        System.out.println("UUID " + uuid + " resolves to " + resolved.getNameLabel(conn));
        System.out.println("Same object: " + resolved.equals(vm));
        System.out.println("OK: find-by-uuid");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
UUID 00000001-0000-0000-8d00-000000000000 resolves to web-01
Same object: true
OK: find-by-uuid
```

</details>
