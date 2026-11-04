<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Trace API calls

Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part of your application's distributed trace.

Workflow `trace-api-calls`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/GettingStarted/TraceApiCalls.cs`](../../csharp/GettingStarted/TraceApiCalls.cs)

```csharp
/// <summary>
/// Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part
/// of your application's distributed trace.
/// </summary>
/// <example>
/// <code>
/// Workflows.TraceApiCalls("https://xenserver", "root", password);
/// </code>
/// </example>
/// <remarks>
/// The SDK sends the current <see cref="Activity"/> to the pool as a W3C traceparent header with every
/// call. In an application instrumented with OpenTelemetry, the request you are serving is already the
/// current activity, so its trace carries on into the pool with no extra code; this example starts an
/// activity of its own instead. The SDK's builds for .NET 8 and later also record each call as an
/// activity, "XenAPI/&lt;method&gt;": add its source to your tracer (<c>.AddSource("XenServer.*")</c>)
/// to export those too.
/// </remarks>
public static void TraceApiCalls(string url, string user, string password)
{
    // Recorded: the trace is sampled, which the traceparent's flags tell the pool.
    using var trace = new Activity("trace-api-calls") { ActivityTraceFlags = ActivityTraceFlags.Recorded }
        .SetIdFormat(ActivityIdFormat.W3C).Start();
    Console.WriteLine($"Trace {trace.TraceId}: each call sends traceparent: {trace.Id}");

    var session = Connect(url, user, password);
    var hosts = Host.get_all(session);
    Console.WriteLine($"The pool has {hosts.Count} hosts");
    Console.WriteLine("OK: trace-api-calls");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Trace ddab3a194e6bd424084d4b639027d53a: each call sends traceparent: 00-ddab3a194e6bd424084d4b639027d53a-aef9b328e6a85c5a-01
The pool has 2 hosts
OK: trace-api-calls
```

</details>

## Python

Source: [`python/getting_started/trace_api_calls.py`](../../python/getting_started/trace_api_calls.py)

```python
"""Trace API calls.

Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part
of your application's distributed trace.

Run it::

    trace_api_calls("https://xenserver", "root", password)
"""

import os
import ssl
import xmlrpc.client

import XenAPI


def trace_api_calls(url, username, password):
    """Send a W3C trace context (a traceparent header) with every call, so the work the pool does for
    them is recorded as part of your application's distributed trace.

    XenAPI.Session sends the extra headers its transport is given. In an application instrumented with
    OpenTelemetry you would take the traceparent from the current span (opentelemetry.propagate.inject)
    rather than make one up as this does."""
    # version 00, a 16-byte trace id, the 8-byte id of the calling span, and flags 01 (sampled)
    trace_id = os.urandom(16).hex()
    traceparent = "00-%s-%s-01" % (trace_id, os.urandom(8).hex())

    def login(url):
        headers = [("traceparent", traceparent)]
        if url.startswith("https:"):
            # The host's certificate is self-signed: skip its validation, as connect() does.
            transport = xmlrpc.client.SafeTransport(context=ssl._create_unverified_context(), headers=headers)
        else:
            transport = xmlrpc.client.Transport(headers=headers)
        session = XenAPI.Session(url, transport=transport)
        session.login_with_password(username, password, "1.0", "sdk-examples")
        return session

    try:
        session = login(url)
    except XenAPI.Failure as e:
        if e.details[0] != "HOST_IS_SLAVE":
            raise
        session = login("https://%s" % e.details[1])  # the coordinator, as connect() does
    print("Trace %s: each call sends traceparent: %s" % (trace_id, traceparent))

    hosts = session.xenapi.host.get_all()
    print("The pool has %d hosts" % len(hosts))
    print("OK: trace-api-calls")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Trace 9310344291e2434653ed629222c7a7d7: each call sends traceparent: 00-9310344291e2434653ed629222c7a7d7-94e497b0d9528326-01
The pool has 2 hosts
OK: trace-api-calls
```

</details>

## Java

*Not available in Java: The Java SDK cannot add an HTTP header to the requests it sends.*

## Go

Source: [`go/trace_api_calls.go`](../../go/trace_api_calls.go)

```go
package main

import (
	"crypto/rand"
	"fmt"

	"go/xenapi"
)

// traceAPICalls sends a W3C trace context (a traceparent header) with every call, so the work the pool
// does for them is recorded as part of your application's distributed trace. ClientOpts.Headers are
// sent with every request a session makes. In an application instrumented with OpenTelemetry you would
// take the traceparent from the current span (otel.GetTextMapPropagator().Inject) rather than make one
// up as this does.
//
// Run it:
//
//	traceAPICalls("https://xenserver", "root", password)
func traceAPICalls(url, user, password string) {
	// version 00, a 16-byte trace id, the 8-byte id of the calling span, and flags 01 (sampled)
	traceID, spanID := make([]byte, 16), make([]byte, 8)
	_, err := rand.Read(traceID)
	check(err)
	_, err = rand.Read(spanID)
	check(err)
	traceparent := fmt.Sprintf("00-%x-%x-01", traceID, spanID)

	login := func(url string) (*xenapi.Session, error) {
		session := xenapi.NewSession(&xenapi.ClientOpts{URL: url, Headers: map[string]string{"traceparent": traceparent}})
		_, err := session.LoginWithPassword(user, password, "1.0", "sdk-examples")
		return session, err
	}
	session, err := login(url)
	if err != nil {
		if coordinator := coordinatorFromSlaveError(err); coordinator != "" {
			session, err = login("https://" + coordinator) // the coordinator, as connect does
		}
	}
	check(err)
	fmt.Printf("Trace %x: each call sends traceparent: %s\n", traceID, traceparent)

	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	fmt.Printf("The pool has %d hosts\n", len(hosts))
	fmt.Println("OK: trace-api-calls")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Trace 61a6b943c0b2e6c003869d43551a2d12: each call sends traceparent: 00-61a6b943c0b2e6c003869d43551a2d12-103c0241953039c8-01
The pool has 2 hosts
OK: trace-api-calls
```

</details>

## PowerShell

Source: [`powershell/GettingStarted/Invoke-TraceApiCalls.ps1`](../../powershell/GettingStarted/Invoke-TraceApiCalls.ps1)

```powershell
function Invoke-TraceApiCalls {
    <#
    .SYNOPSIS
        Trace API calls.
    .DESCRIPTION
        Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part
        of your application's distributed trace.

        The module's client sends the current System.Diagnostics.Activity to the server as a traceparent
        header, so start one around the calls (in an application instrumented with OpenTelemetry, the
        current activity is already your span).
    .EXAMPLE
        Invoke-TraceApiCalls -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $trace = [System.Diagnostics.Activity]::new("trace-api-calls")
    # Recorded: the trace is sampled, which the traceparent's flags tell the pool.
    $trace.ActivityTraceFlags = [System.Diagnostics.ActivityTraceFlags]::Recorded
    $null = $trace.SetIdFormat([System.Diagnostics.ActivityIdFormat]::W3C).Start()
    try {
        Write-Host "Trace $($trace.TraceId): each call sends traceparent: $($trace.Id)"
        $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
        $hosts = @(Get-XenHost)
        Write-Host "The pool has $($hosts.Count) hosts"
        Write-Host "OK: trace-api-calls"
        $session | Disconnect-XenServer
    }
    finally {
        $trace.Stop()
    }
}
```

<details><summary>Sample output</summary>

```text
Trace 6d88ec29a21fdae47fa90bdd4f63295f: each call sends traceparent: 00-6d88ec29a21fdae47fa90bdd4f63295f-75be70d628489aae-01
The pool has 2 hosts
OK: trace-api-calls
```

</details>

## xe CLI

Source: [`cli/getting-started/trace-api-calls.sh`](../../cli/getting-started/trace-api-calls.sh)

```bash
# Trace API calls.
#
# Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part of your
# application's distributed trace.
#
# Run it:
#   ./workflows.sh trace-api-calls https://xenserver root "$password"

# Send a W3C trace context with every command, so the work the pool does for them is recorded as part of
# your application's distributed trace. xe sends $TRACEPARENT to the server as a traceparent header (or
# take --traceparent <value>); in a traced script, export the caller's own. The Windows xe.exe that
# ships with XenCenter does not send one.
trace_api_calls() {
    # version 00, a 16-byte trace id, the 8-byte id of the calling span, and flags 01 (sampled)
    local trace_id span_id
    trace_id=$(od -An -N16 -tx1 /dev/urandom); trace_id=${trace_id//[[:space:]]/}
    span_id=$(od -An -N8 -tx1 /dev/urandom); span_id=${span_id//[[:space:]]/}
    local -x TRACEPARENT="00-$trace_id-$span_id-01"
    echo "Trace $trace_id: each command sends traceparent: $TRACEPARENT"
    local hosts
    hosts=$(xe host-list --minimal)
    echo "The pool has $(count_csv "$hosts") hosts"
    echo "OK: trace-api-calls"
}
```

<details><summary>Sample output</summary>

```text
Trace 5f2cf3fdd709a2642981e9947e86dd5b: each command sends traceparent: 00-5f2cf3fdd709a2642981e9947e86dd5b-15fccaf8a4013bf6-01
The pool has 2 hosts
OK: trace-api-calls
```

</details>
