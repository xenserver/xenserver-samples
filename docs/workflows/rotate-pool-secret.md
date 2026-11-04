<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Rotate the pool secret

Rotate the shared secret that authenticates pool members to each other.

Workflow `rotate-pool-secret`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/RotatePoolSecret.cs`](../../csharp/HostsAndPools/RotatePoolSecret.cs)

```csharp
/// <summary>
/// Rotate the shared secret that authenticates pool members to each other.
/// </summary>
public static void RotatePoolSecret(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var poolRef = Pool.get_all_records(session).Keys.First().opaque_ref;
    Console.WriteLine($"Pool:           {Pool.get_name_label(session, poolRef)}");

    // xapi checks its own preconditions before rotating - HA must be disabled, every host must be
    // live, no rolling pool upgrade may be in progress, and the pool must be licensed for it - and
    // raises a clear error naming which one failed rather than silently refusing. Report that
    // explanation instead of letting an unhandled Failure speak for itself.
    var explanations = new Dictionary<string, string>
    {
        ["HA_IS_ENABLED"] = "HA is enabled on this pool; disable it first.",
        ["CANNOT_CONTACT_HOST"] = "a host in the pool is not reachable.",
        ["NOT_SUPPORTED_DURING_UPGRADE"] = "a rolling pool upgrade is in progress.",
        ["LICENCE_RESTRICTION"] = "this edition is not licensed for pool secret rotation.",
    };
    try
    {
        // A pool-wide operation; existing sessions survive it.
        Pool.rotate_secret(session);
        Console.WriteLine($"Rotated. Still connected: {Pool.get_all(session).Count == 1}");
    }
    catch (Failure f)
    {
        var explanation = explanations.TryGetValue(f.ErrorDescription[0], out var e) ? e : "see the error for detail";
        Console.WriteLine($"Could not rotate the pool secret: {f.ErrorDescription[0]} ({explanation})");
    }
    Console.WriteLine("OK: rotate-pool-secret");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Pool:           sdk-pool
Rotated. Still connected: True
OK: rotate-pool-secret
```

</details>

## Python

Source: [`python/hosts_and_pools/rotate_pool_secret.py`](../../python/hosts_and_pools/rotate_pool_secret.py)

```python
"""Rotate the pool secret.

Rotate the shared secret that authenticates pool members to each other.
"""

import XenAPI

from connection import connect


def rotate_pool_secret(url, username, password):
    """Rotate the shared secret pool members authenticate to each other with.

    xapi checks its own preconditions before rotating - HA must be disabled, every host must be
    live, no rolling pool upgrade may be in progress, and the pool must be licensed for it - and
    raises a clear error naming which one failed rather than silently refusing. Report that
    explanation instead of letting an unhandled XenAPI.Failure speak for itself."""
    session = connect(url, username, password)
    pool_ref = list(session.xenapi.pool.get_all_records().keys())[0]
    print("Pool:           %s" % session.xenapi.pool.get_name_label(pool_ref))

    explanations = {
        "HA_IS_ENABLED": "HA is enabled on this pool; disable it first.",
        "CANNOT_CONTACT_HOST": "a host in the pool is not reachable.",
        "NOT_SUPPORTED_DURING_UPGRADE": "a rolling pool upgrade is in progress.",
        "LICENCE_RESTRICTION": "this edition is not licensed for pool secret rotation.",
    }
    try:
        # A pool-wide operation; existing sessions survive it.
        session.xenapi.pool.rotate_secret()
        print("Rotated. Still connected: %s" % (len(session.xenapi.pool.get_all()) == 1))
    except XenAPI.Failure as e:
        print("Could not rotate the pool secret: %s (%s)"
              % (e.details[0], explanations.get(e.details[0], "see the error for detail")))
    print("OK: rotate-pool-secret")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Pool:           sdk-pool
Rotated. Still connected: True
OK: rotate-pool-secret
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/RotatePoolSecret.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/RotatePoolSecret.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import static com.xenserver.samples.PoolConnection.connect;

public final class RotatePoolSecret {
    private RotatePoolSecret() {
    }

    /**
     * Rotate the pool secret.
     *
     * <p>Rotate the shared secret that authenticates pool members to each other.
     *
     * <p>xapi checks its own preconditions before rotating - HA must be disabled, every host must be live,
     * no rolling pool upgrade may be in progress, and the pool must be licensed for it - and raises a
     * clear error naming which one failed rather than silently refusing. Report that explanation instead
     * of letting an unhandled XenAPIException speak for itself. Still reports OK either way - the point is
     * demonstrating the precondition handling, not requiring the rotation to succeed.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        System.out.println("Pool:           " + pool.getNameLabel(conn));

        try {
            // A pool-wide operation; existing sessions survive it.
            Pool.rotateSecret(conn);
            System.out.println("Rotated. Still connected: " + (Pool.getAll(conn).size() == 1));
        } catch (Types.HaIsEnabled e) {
            System.out.println("Could not rotate the pool secret: HA is enabled on this pool; disable it first.");
        } catch (Types.CannotContactHost e) {
            System.out.println("Could not rotate the pool secret: a host in the pool is not reachable.");
        } catch (Types.NotSupportedDuringUpgrade e) {
            System.out.println("Could not rotate the pool secret: a rolling pool upgrade is in progress.");
        } catch (Types.LicenceRestriction e) {
            System.out.println("Could not rotate the pool secret: this edition is not licensed for pool secret rotation.");
        } catch (Types.XenAPIException e) {
            System.out.println("Could not rotate the pool secret: " + e.shortDescription);
        }
        System.out.println("OK: rotate-pool-secret");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
Pool:           sdk-pool
Rotated. Still connected: true
OK: rotate-pool-secret
```

</details>

## Go

Source: [`go/rotate_pool_secret.go`](../../go/rotate_pool_secret.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// rotatePoolSecret - Rotate the pool secret.
//
// Rotate the shared secret that authenticates pool members to each other.
func rotatePoolSecret(url, user, password string) {
	session := connect(url, user, password)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	name, _ := xenapi.Pool.GetNameLabel(session, pools[0])
	fmt.Printf("Pool:           %s\n", name)

	// xapi checks its own preconditions before rotating - HA must be disabled, every host must be
	// live, no rolling pool upgrade may be in progress, and the pool must be licensed for it - and
	// raises a clear error naming which one failed rather than silently refusing. Report that
	// explanation instead of letting the failure speak for itself; the point here is demonstrating
	// the precondition handling, not requiring the rotation to succeed.
	explanations := map[string]string{
		xenapi.ErrorHaIsEnabled:               "HA is enabled on this pool; disable it first.",
		xenapi.ErrorCannotContactHost:         "a host in the pool is not reachable.",
		xenapi.ErrorNotSupportedDuringUpgrade: "a rolling pool upgrade is in progress.",
		xenapi.ErrorLicenceRestriction:        "this edition is not licensed for pool secret rotation.",
	}
	if err := xenapi.Pool.RotateSecret(session); err != nil {
		code := failureCode(err)
		explanation, ok := explanations[code]
		if !ok {
			explanation = "see the error for detail"
		}
		fmt.Printf("Could not rotate the pool secret: %s (%s)\n", code, explanation)
	} else {
		after, _ := xenapi.Pool.GetAll(session)
		fmt.Printf("Rotated. Still connected: %t\n", len(after) == 1)
	}
	fmt.Println("OK: rotate-pool-secret")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Pool:           sdk-pool
Rotated. Still connected: true
OK: rotate-pool-secret
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-RotatePoolSecret.ps1`](../../powershell/HostsAndPools/Invoke-RotatePoolSecret.ps1)

```powershell
function Invoke-RotatePoolSecret {
    <#
    .SYNOPSIS
        Rotate the pool secret.
    .DESCRIPTION
        Rotate the shared secret that authenticates pool members to each other.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    Write-Host "Pool:           $($pool.name_label)"

    # xapi checks its own preconditions before rotating - HA must be disabled, every host must be live,
    # no rolling pool upgrade may be in progress, and the pool must be licensed for it - and raises a
    # clear error naming which one failed rather than silently refusing. Report that explanation instead
    # of letting an unhandled failure speak for itself.
    $explanations = @{
        "HA_IS_ENABLED"                 = "HA is enabled on this pool; disable it first."
        "CANNOT_CONTACT_HOST"           = "a host in the pool is not reachable."
        "NOT_SUPPORTED_DURING_UPGRADE"  = "a rolling pool upgrade is in progress."
        "LICENCE_RESTRICTION"           = "this edition is not licensed for pool secret rotation."
    }
    try {
        # A pool-wide operation; existing sessions survive it.
        Invoke-XenPool -Ref $pool.opaque_ref -XenAction RotateSecret
        Write-Host "Rotated. Still connected: $(@(Get-XenPool).Count -eq 1)"
    }
    catch {
        $ex = $_.Exception
        while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
        $code = if ($ex -and $ex.ErrorDescription) { $ex.ErrorDescription[0] } else { $_.Exception.Message }
        $explanation = if ($explanations.ContainsKey($code)) { $explanations[$code] } else { "see the error for detail" }
        Write-Host "Could not rotate the pool secret: $code ($explanation)"
    }
    Write-Host "OK: rotate-pool-secret"
    Disconnect-XenServer -Session $session
}
```

<details><summary>Sample output</summary>

```text
Pool:           sdk-pool
Rotated. Still connected: True
OK: rotate-pool-secret
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/rotate-pool-secret.sh`](../../cli/hosts-and-pools/rotate-pool-secret.sh)

```bash
# Rotate the pool secret.
#
# Rotate the shared secret that authenticates pool members to each other.
#
# Run it:
#   ./workflows.sh rotate-pool-secret https://xenserver root "$password"

rotate_pool_secret() {
    echo "Pool:           $(xe pool-list params=name-label --minimal)"
    # xapi checks its own preconditions before rotating - HA must be disabled, every host must be live, no
    # rolling pool upgrade may be in progress, and the pool must be licensed for it - and xe already prints
    # a clear explanation of whichever one failed, so report that instead of letting the raw failure abort
    # the script. A pool-wide operation; existing sessions survive it.
    if err=$(xe pool-secret-rotate 2>&1); then
        echo "Rotated. Still connected: $(count_csv "$(xe pool-list --minimal)")"
    else
        echo "Could not rotate the pool secret: $err"
    fi
    echo "OK: rotate-pool-secret"
}
```

<details><summary>Sample output</summary>

```text
Pool:           sdk-pool
Rotated. Still connected: 1
OK: rotate-pool-secret
```

</details>
