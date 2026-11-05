<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Raise and dismiss alerts

List the pool's alerts, then dismiss one — what the Notifications view does.

Workflow `dismiss-alerts`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/DismissAlerts.cs`](../../csharp/HostsAndPools/DismissAlerts.cs)

```csharp
/// <summary>
/// List the pool's alerts, then dismiss one — what the Notifications view does.
/// </summary>
public static void DismissAlerts(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var messages = Message.get_all_records(session);
    Console.WriteLine($"Alerts:         {messages.Count}");

    var first = messages.FirstOrDefault();
    if (first.Key == null)
    {
        Console.WriteLine("No alerts to dismiss.");
    }
    else
    {
        Console.WriteLine($"Dismissing:     {first.Value.name} (priority {first.Value.priority})");
        // Dismissing an alert is this one call.
        Message.destroy(session, first.Key);
        Console.WriteLine($"Alerts left:    {Message.get_all_records(session).Count}");
    }
    Console.WriteLine("OK: dismiss-alerts");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Alerts:         0
No alerts to dismiss.
OK: dismiss-alerts
```

</details>

## Python

Source: [`python/hosts_and_pools/dismiss_alerts.py`](../../python/hosts_and_pools/dismiss_alerts.py)

```python
"""Raise and dismiss alerts.

List the pool's alerts, then dismiss one — what the Notifications view does.
"""

from connection import connect


def dismiss_alerts(url, username, password):
    """List the pool's alerts and dismiss one, as the Notifications view does."""
    session = connect(url, username, password)
    messages = session.xenapi.message.get_all_records()
    print("Alerts:         %d" % len(messages))

    if not messages:
        print("No alerts to dismiss.")
    else:
        ref = sorted(messages.keys())[0]
        print("Dismissing:     %s (priority %s)" % (messages[ref]["name"], messages[ref]["priority"]))
        session.xenapi.message.destroy(ref)
        print("Alerts left:    %d" % len(session.xenapi.message.get_all_records()))
    print("OK: dismiss-alerts")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Alerts:         0
No alerts to dismiss.
OK: dismiss-alerts
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/DismissAlerts.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/DismissAlerts.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Message;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class DismissAlerts {
    private DismissAlerts() {
    }

    /**
     * Raise and dismiss alerts.
     *
     * <p>List the pool's alerts, then dismiss one — what the Notifications view does.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Map<Message, Message.Record> messages = Message.getAllRecords(conn);
        System.out.println("Alerts:         " + messages.size());

        if (messages.isEmpty()) {
            System.out.println("No alerts to dismiss.");
        } else {
            Map.Entry<Message, Message.Record> first = messages.entrySet().iterator().next();
            System.out.println("Dismissing:     " + first.getValue().name
                    + " (priority " + first.getValue().priority + ")");
            first.getKey().destroy(conn);
            System.out.println("Alerts left:    " + Message.getAllRecords(conn).size());
        }
        System.out.println("OK: dismiss-alerts");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
Alerts:         0
No alerts to dismiss.
OK: dismiss-alerts
```

</details>

## Go

Source: [`go/dismiss_alerts.go`](../../go/dismiss_alerts.go)

```go
package main

import (
	"fmt"
	"sort"

	"go/xenapi"
)

// dismissAlerts - Raise and dismiss alerts.
//
// List the pool's alerts, then dismiss one — what the Notifications view does.
func dismissAlerts(url, user, password string) {
	session := connect(url, user, password)
	messages, err := xenapi.Message.GetAllRecords(session)
	check(err)
	fmt.Printf("Alerts:         %d\n", len(messages))

	if len(messages) == 0 {
		fmt.Println("No alerts to dismiss.")
	} else {
		// Sorted, for a deterministic choice of which one to dismiss.
		refs := make([]string, 0, len(messages))
		for ref := range messages {
			refs = append(refs, string(ref))
		}
		sort.Strings(refs)
		ref := xenapi.MessageRef(refs[0])
		m := messages[ref]
		fmt.Printf("Dismissing:     %s (priority %d)\n", m.Name, m.Priority)
		check(xenapi.Message.Destroy(session, ref))
		left, _ := xenapi.Message.GetAllRecords(session)
		fmt.Printf("Alerts left:    %d\n", len(left))
	}
	fmt.Println("OK: dismiss-alerts")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Alerts:         0
No alerts to dismiss.
OK: dismiss-alerts
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-DismissAlerts.ps1`](../../powershell/HostsAndPools/Invoke-DismissAlerts.ps1)

```powershell
function Invoke-DismissAlerts {
    <#
    .SYNOPSIS
        Raise and dismiss alerts.
    .DESCRIPTION
        List the pool's alerts, then dismiss one — what the Notifications view does.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $messages = @(Get-XenMessage)
    Write-Host "Alerts:         $($messages.Count)"

    if ($messages.Count -eq 0) {
        Write-Host "No alerts to dismiss."
    } else {
        $first = $messages[0]
        Write-Host "Dismissing:     $($first.name) (priority $($first.priority))"
        Remove-XenMessage -Ref $first.opaque_ref
        Write-Host "Alerts left:    $(@(Get-XenMessage).Count)"
    }
    Write-Host "OK: dismiss-alerts"
    Disconnect-XenServer -Session $session
}
```

<details><summary>Sample output</summary>

```text
Alerts:         0
No alerts to dismiss.
OK: dismiss-alerts
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/dismiss-alerts.sh`](../../cli/hosts-and-pools/dismiss-alerts.sh)

```bash
# Raise and dismiss alerts.
#
# List the pool's alerts, then dismiss one — what the Notifications view does.
#
# Run it:
#   ./workflows.sh dismiss-alerts https://xenserver root "$password"

dismiss_alerts() {
    echo "Alerts:         $(count_csv "$(xe message-list --minimal)")"
    # Sorted, for a deterministic choice of which one to dismiss (message-list's own order is not).
    msg=$(xe message-list --minimal | tr ',' '\n' | sort | head -n 1)
    if [ -n "$msg" ]; then
        echo "Dismissing:     $(xe message-param-get uuid=$msg param-name=name)"
        xe message-destroy uuid=$msg
        echo "Alerts left:    $(count_csv "$(xe message-list --minimal)")"
    else
        echo "No alerts to dismiss."
    fi
    echo "OK: dismiss-alerts"
}
```

<details><summary>Sample output</summary>

```text
Alerts:         0
No alerts to dismiss.
OK: dismiss-alerts
```

</details>
