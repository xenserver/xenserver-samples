<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Handle an API error

Catch an API failure and inspect its error code and parameters — the shape of every error the API returns, and how to react to it robustly.

Workflow `error-handling`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/GettingStarted/Invoke-ErrorHandling.ps1`](../../powershell/GettingStarted/Invoke-ErrorHandling.ps1)

```powershell
function Invoke-ErrorHandling {
    <#
    .SYNOPSIS
        Handle an API error.
    .DESCRIPTION
        Catch an API failure and inspect its error code and parameters — the shape of every error the API
        returns, and how to react to it robustly.
    .EXAMPLE
        Invoke-ErrorHandling -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # XenAPI errors surface as a failure whose ErrorDescription is [CODE, param1, param2, ...]. Any
    # cmdlet that reaches the server can raise one - here we deliberately act on a VM UUID that doesn't
    # exist. The module may wrap the failure, so walk the InnerException chain to the ErrorDescription.
    try {
        Set-XenVM -Uuid (New-Guid).Guid -NameLabel "will-not-apply"
        Write-Host "unexpected: no error"
    }
    catch {
        $ex = $_.Exception
        while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
        if ($ex -and $ex.ErrorDescription) { Write-Host "Caught expected failure: $($ex.ErrorDescription[0])" }
        else { Write-Host "Caught expected failure: $($_.Exception.Message)" }
    }
    Write-Host "OK: error-handling"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Caught expected failure: UUID_INVALID
OK: error-handling
```

</details>

## xe CLI

Source: [`cli/getting-started/error-handling.sh`](../../cli/getting-started/error-handling.sh)

```bash
# Handle an API error.
#
# Catch an API failure and inspect its error code and parameters — the shape of every error the API returns,
# and how to react to it robustly.
#
# Run it:
#   ./workflows.sh error-handling https://xenserver root "$password"

error_handling() {
    # xe prints a failed call's error (its code and parameters, or a friendly rendering of a common
    # one) to stderr; capture it instead of letting it go straight to the terminal.
    if out=$(xe vm-param-get uuid=this-uuid-does-not-exist param-name=uuid 2>&1); then
        echo "unexpected: no error"
    else
        echo "Caught expected failure:"
        echo "$out"
    fi
    echo "OK: error-handling"
}
```

<details><summary>Example output</summary>

```text
Caught expected failure:
The uuid you supplied was invalid.
type: VM
uuid: this-uuid-does-not-exist
[ERROR] Command Exit 1
OK: error-handling
```

</details>

## Python

Source: [`python/getting_started/error_handling.py`](../../python/getting_started/error_handling.py)

```python
"""Handle an API error.

Catch an API failure and inspect its error code and parameters — the shape of every error the API
returns, and how to react to it robustly.

Run it::

    error_handling("https://xenserver", "root", password)
"""

import XenAPI

from connection import connect


def error_handling(url, username, password):
    """XenAPI errors surface as a XenAPI.Failure whose details are [CODE, param1, param2, ...]."""
    session = connect(url, username, password)
    try:
        session.xenapi.host.get_by_uuid("this-uuid-does-not-exist")
        print("unexpected: no error")
    except XenAPI.Failure as f:
        print("Caught expected failure: %s" % f.details[0])
        print("Error parameters: %s" % f.details[1:])
    print("OK: error-handling")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Caught expected failure: UUID_INVALID
Error parameters: ['host', 'this-uuid-does-not-exist']
OK: error-handling
```

</details>

## C# (.NET)

Source: [`csharp/GettingStarted/ErrorHandling.cs`](../../csharp/GettingStarted/ErrorHandling.cs)

```csharp
/// <summary>
/// Catch an API failure and inspect its error code and parameters — the shape of every error the API
/// returns, and how to react to it robustly.
/// </summary>
/// <example>
/// <code>
/// Workflows.ErrorHandling("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ErrorHandling(string url, string user, string password)
{
    var session = Connect(url, user, password);
    // XenAPI errors surface as a Failure whose ErrorDescription is [CODE, param1, param2, ...].
    try
    {
        Host.get_by_uuid(session, "this-uuid-does-not-exist");
        Console.WriteLine("unexpected: no error");
    }
    catch (Failure f)
    {
        Console.WriteLine($"Caught expected failure: {f.ErrorDescription[0]}");
        // Failure.Message (ShortMessage is obsolete and returns the same text).
        Console.WriteLine($"Short message: {f.Message}");
    }
    Console.WriteLine("OK: error-handling");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Caught expected failure: UUID_INVALID
Short message: The uuid you supplied was invalid.
OK: error-handling
```

</details>

## Go

Source: [`go/error_handling.go`](../../go/error_handling.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// errorHandling - Handle an API error.
//
// Catch an API failure and inspect its error code and parameters — the shape of every error the API
// returns, and how to react to it robustly.
//
// Run it:
//
//	errorHandling("https://xenserver", "root", password)
func errorHandling(url, user, password string) {
	session := connect(url, user, password)
	// XenAPI errors surface as an error whose text carries the XenAPI error code.
	_, err := xenapi.Host.GetByUUID(session, "this-uuid-does-not-exist")
	if err != nil {
		fmt.Printf("Caught expected failure: %s\n", err)
	} else {
		fmt.Println("unexpected: no error")
	}
	fmt.Println("OK: error-handling")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Caught expected failure: API error: code 1, message UUID_INVALID, data [host this-uuid-does-not-exist]
OK: error-handling
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/gettingstarted/ErrorHandling.java`](../../java/src/main/java/com/xenserver/samples/gettingstarted/ErrorHandling.java)

```java
package com.xenserver.samples.gettingstarted;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import static com.xenserver.samples.PoolConnection.connect;

public final class ErrorHandling {
    private ErrorHandling() {
    }

    /**
     * Handle an API error.
     *
     * <p>Catch an API failure and inspect its error code and parameters — the shape of every error the API
     * returns, and how to react to it robustly.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ErrorHandling.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        // XenAPI errors surface as a XenAPIException. Specific errors are typed subclasses (e.g.
        // UuidInvalid): the class name identifies the error. getMessage() is NOT the readable text here:
        // in Java SDKs up to 26.22 the generated XenAPIException never calls super(message), so
        // Throwable.getMessage() is null for every typed XenAPI exception. shortDescription and
        // errorDescription carry the real text, and work with every SDK version.
        try {
            Host.getByUuid(conn, "this-uuid-does-not-exist");
            System.out.println("unexpected: no error");
        } catch (Types.XenAPIException e) {
            System.out.println("Caught expected failure: " + e.getClass().getSimpleName());
            System.out.println("Short message: " + e.shortDescription);
            if (e.errorDescription != null)
                System.out.println("Error fields: " + java.util.Arrays.toString(e.errorDescription));
        }
        System.out.println("OK: error-handling");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Caught expected failure: UuidInvalid
Short message: The uuid you supplied was invalid.
OK: error-handling
```

</details>
