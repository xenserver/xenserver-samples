<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Event monitoring

Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a client's view of the pool live.

Workflow `events`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/GettingStarted/Events.cs`](../../csharp/GettingStarted/Events.cs)

```csharp
/// <summary>
/// Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a
/// client's view of the pool live.
/// </summary>
/// <example>
/// <code>
/// Workflows.Events("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void Events(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);
    var classes = new[] { "VM" };
    var batch = (EventBatch)Event.from(session, classes, "", 1.0);
    var token = batch.token;
    Console.WriteLine("Established event token after initial snapshot.");

    var vmRef = VmByName(session, vmName);
    var original = VM.get_name_description(session, vmRef);
    VM.set_name_description(session, vmRef, "changed-to-trigger-event");

    batch = (EventBatch)Event.from(session, classes, token, 5.0);
    Console.WriteLine($"Received {batch.events.Length} event(s) after the change.");
    foreach (var ev in batch.events.Take(3))
        Console.WriteLine($"  - {ev.operation} {ev.class_}");

    VM.set_name_description(session, vmRef, original); // put it back
    Console.WriteLine("OK: events");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Established event token after initial snapshot.
Received 1 event(s) after the change.
  - mod vm
OK: events
```

</details>

## Python

Source: [`python/getting_started/events.py`](../../python/getting_started/events.py)

```python
"""Event monitoring.

Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a
client's view of the pool live.

Run it::

    events("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def events(url, username, password, vm_name):
    """Watch the event stream and observe a change we make to the named VM land as an event."""
    session = connect(url, username, password)
    event_from = getattr(session.xenapi.event, "from")  # 'from' is a Python keyword

    # An empty token yields the current world and a fresh token to watch from.
    batch = event_from(["VM"], "", 1.0)
    token = batch["token"]
    print("Established event token after initial snapshot.")

    # Make a change, then poll for it.
    vm_ref = vm_by_name(session, vm_name)
    original = session.xenapi.VM.get_name_description(vm_ref)
    session.xenapi.VM.set_name_description(vm_ref, "changed-to-trigger-event")

    batch = event_from(["VM"], token, 5.0)
    print("Received %d event(s) after the change." % len(batch["events"]))
    for ev in batch["events"][:3]:
        print("  - %s %s" % (ev["operation"], ev["class"]))

    session.xenapi.VM.set_name_description(vm_ref, original)  # put it back
    print("OK: events")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Established event token after initial snapshot.
Received 1 event(s) after the change.
  - mod vm
OK: events
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/gettingstarted/Events.java`](../../java/src/main/java/com/xenserver/samples/gettingstarted/Events.java)

```java
package com.xenserver.samples.gettingstarted;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Event;
import com.xensource.xenapi.EventBatch;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import java.util.LinkedHashSet;
import java.util.Set;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class Events {
    private Events() {
    }

    /**
     * Event monitoring.
     *
     * <p>Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a
     * client's view of the pool live.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * Events.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        Set<String> classes = new LinkedHashSet<>();
        classes.add("VM");

        EventBatch batch = Event.from(conn, classes, "", 1.0);
        String token = batch.token;
        System.out.println("Established event token after initial snapshot.");

        VM vm = vmByName(conn, vmName);
        String original = vm.getNameDescription(conn);
        vm.setNameDescription(conn, "changed-to-trigger-event");

        batch = Event.from(conn, classes, token, 5.0);
        System.out.println("Received " + batch.events.size() + " event(s) after the change.");
        int shown = 0;
        for (Event.Record ev : batch.events) {
            if (shown++ >= 3) break;
            System.out.println("  - " + ev.operation + " " + ev.clazz);
        }

        vm.setNameDescription(conn, original); // put it back
        System.out.println("OK: events");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
Established event token after initial snapshot.
Received 1 event(s) after the change.
  - mod vm
OK: events
```

</details>

## Go

Source: [`go/events.go`](../../go/events.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// events - Event monitoring.
//
// Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a
// client's view of the pool live.
//
// Run it:
//
//	events("https://xenserver", "root", password, "web-01")
func events(url, user, password, vmName string) {
	session := connect(url, user, password)
	classes := []string{"VM"}
	batch, err := xenapi.Event.From(session, classes, "", 1.0)
	check(err)
	token := batch.Token
	fmt.Println("Established event token after initial snapshot.")

	vmRef := vmByName(session, vmName)
	original, err := xenapi.VM.GetNameDescription(session, vmRef)
	check(err)
	check(xenapi.VM.SetNameDescription(session, vmRef, "changed-to-trigger-event"))

	batch, err = xenapi.Event.From(session, classes, token, 5.0)
	check(err)
	fmt.Printf("Received %d event(s) after the change.\n", len(batch.Events))
	for i, ev := range batch.Events {
		if i >= 3 {
			break
		}
		fmt.Printf("  - %s %s\n", ev.Operation, ev.Class)
	}

	check(xenapi.VM.SetNameDescription(session, vmRef, original)) // put it back
	fmt.Println("OK: events")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Established event token after initial snapshot.
Received 1 event(s) after the change.
  - mod vm
OK: events
```

</details>

## PowerShell

Source: [`powershell/GettingStarted/Invoke-Events.ps1`](../../powershell/GettingStarted/Invoke-Events.ps1)

```powershell
function Invoke-Events {
    <#
    .SYNOPSIS
        Event monitoring.
    .DESCRIPTION
        Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a
        client's view of the pool live.
    .EXAMPLE
        Invoke-Events -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # An empty token returns the current snapshot and a token; passing that token back long-polls
    # until something changes. (Get-XenEventBatch is our thin wrapper - see the top of the file.)
    $batch = Get-XenEventBatch -Session $session -Classes VM -Token "" -Timeout 1.0
    $token = $batch.token
    Write-Host "Established event token after initial snapshot."

    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $original = $vm.name_description
    $vm | Set-XenVM -NameDescription "changed-to-trigger-event"

    $batch = Get-XenEventBatch -Session $session -Classes VM -Token $token -Timeout 5.0
    Write-Host "Received $(@($batch.events).Count) event(s) after the change."
    $batch.events | Select-Object -First 3 | ForEach-Object { Write-Host "  - $($_.operation) $($_.class)" }

    $vm | Set-XenVM -NameDescription $original   # put it back
    Write-Host "OK: events"
    $session | Disconnect-XenServer
}

function Get-XenEventBatch {
    <#
    .SYNOPSIS
        The XenServer PowerShell module ships no event cmdlet, so this thin wrapper calls the JSON-RPC
        event.from method directly with Invoke-RestMethod (Connect-Example has already trusted the server's
        certificate, so no extra TLS setup is needed).
    .DESCRIPTION
        An empty token returns the current snapshot plus a token to watch from; passing that token back
        long-polls for changes.
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string[]]$Classes,
        [string]$Token = "",
        [double]$Timeout = 5.0
    )
    $body = @{
        jsonrpc = "2.0"; id = 1; method = "event.from"
        params  = @($Session.opaque_ref, $Classes, $Token, $Timeout)
    } | ConvertTo-Json -Depth 6
    $resp = Invoke-RestMethod -Uri "$($Session.Url)/jsonrpc" -Method Post -Body $body -ContentType "application/json"
    if ($resp.error) { throw "event.from failed: $($resp.error | ConvertTo-Json -Compress)" }
    return $resp.result
}
```

<details><summary>Sample output</summary>

```text
Established event token after initial snapshot.
Received 1 event(s) after the change.
  - mod vm
OK: events
```

</details>

## xe CLI

Source: [`cli/getting-started/events.sh`](../../cli/getting-started/events.sh)

```bash
# Event monitoring.
#
# Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a client's
# view of the pool live.
#
# Run it:
#   ./workflows.sh events https://xenserver root "$password"

events() {
    vm=$(vm_uuid web-01)
    original=$(xe vm-param-get uuid=$vm param-name=name-description)

    # event-wait blocks until the object matches the condition, so there has to be something left to
    # happen when it starts watching: make the change in the background, timed to land only after the
    # foreground event-wait below is already watching for it.
    (sleep 2; xe vm-param-set uuid=$vm name-description="changed-to-trigger-event") &
    xe event-wait class=vm uuid=$vm name-description="changed-to-trigger-event"
    echo "Observed web-01's name-description change via event-wait"

    xe vm-param-set uuid=$vm name-description="$original"  # put it back
    echo "OK: events"
}
```

<details><summary>Sample output</summary>

```text
Observed web-01's name-description change via event-wait
OK: events
```

</details>
