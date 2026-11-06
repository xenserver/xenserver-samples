<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage SSH access

Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it again — the pool-level call fans out to every host.

Workflow `manage-ssh-access`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ManageSshAccess.ps1`](../../powershell/HostsAndPools/Invoke-ManageSshAccess.ps1)

```powershell
function Invoke-ManageSshAccess {
    <#
    .SYNOPSIS
        Manage SSH access.
    .DESCRIPTION
        Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it again
        — the pool-level call fans out to every host.
    .EXAMPLE
        Invoke-ManageSshAccess -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool
    # Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
    $before = @(Get-XenHost | ForEach-Object {
        [pscustomobject]@{ Ref = $_.opaque_ref; Enabled = $_.ssh_enabled; Timeout = $_.ssh_enabled_timeout } })

    # Timed access is the point: set the timeout first and the server stamps an expiry when SSH is
    # enabled, so a window opened for troubleshooting closes itself. set_ssh_enabled_timeout is itself a
    # pool-wide fan-out call, exactly like enable_ssh/disable_ssh - no need to loop hosts for it either.
    $pool | Set-XenPool -SshEnabledTimeout 3600

    # The pool action fans out to every host, so there is no need to loop for the enable itself.
    Invoke-XenPool -Pool $pool -XenAction EnableSsh
    Get-XenHost | ForEach-Object {
        Write-Host "$($_.name_label): ssh enabled=$($_.ssh_enabled), expires $($_.ssh_expiry.ToString('yyyyMMddTHH:mm:ssZ'))"
    }

    Invoke-XenPool -Pool $pool -XenAction DisableSsh
    Write-Host ("After disable: " + ((Get-XenHost | ForEach-Object { "$($_.name_label)=$($_.ssh_enabled)" }) -join ', '))

    foreach ($h in $before) {
        # first: enabling stamps the expiry from it
        Get-XenHost -Ref $h.Ref | Set-XenHost -SshEnabledTimeout $h.Timeout
        if ($h.Enabled) { Invoke-XenHost -Ref $h.Ref -XenAction EnableSsh }
    }
    Write-Host "OK: manage-ssh-access"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
sdk-host1: ssh enabled=True, expires 20260101T09:00:00Z
sdk-host2: ssh enabled=True, expires 20260101T09:00:00Z
After disable: sdk-host1=False, sdk-host2=False
OK: manage-ssh-access
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/manage-ssh-access.sh`](../../cli/hosts-and-pools/manage-ssh-access.sh)

```bash
# Manage SSH access.
#
# Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it again — the
# pool-level call fans out to every host.
#
# Run it:
#   ./workflows.sh manage-ssh-access https://xenserver root "$password"

manage_ssh_access() {
    # Timed access is the point: set the timeout first and the server stamps an expiry when SSH is
    # enabled, so a window opened for troubleshooting closes itself. pool.set_ssh_enabled_timeout is
    # itself a pool-wide fan-out call (exactly like enable_ssh/disable_ssh below), but unlike those two,
    # xe has no CLI command for it at all - only the per-host field is reachable from the CLI - so the
    # host loop here is the only way to do this through xe, not a simplification the SDK languages need.
    # Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
    local before=""
    for h in $(each_csv "$(xe host-list --minimal)"); do
        before="$before $h:$(xe host-param-get uuid=$h param-name=ssh-enabled):$(xe host-param-get uuid=$h param-name=ssh-enabled-timeout)"
        xe host-param-set uuid=$h ssh-enabled-timeout=3600
    done

    # The pool command fans out to every host, so there is no need to loop for the enable itself.
    xe pool-enable-ssh
    for h in $(each_csv "$(xe host-list --minimal)"); do
        echo "$(xe host-param-get uuid=$h param-name=name-label): ssh enabled=$(xe host-param-get uuid=$h param-name=ssh-enabled), expires $(xe host-param-get uuid=$h param-name=ssh-expiry)"
    done

    xe pool-disable-ssh
    states=""
    for h in $(each_csv "$(xe host-list --minimal)"); do
        [ -n "$states" ] && states="$states, "
        states="$states$(xe host-param-get uuid=$h param-name=name-label)=$(xe host-param-get uuid=$h param-name=ssh-enabled)"
    done
    echo "After disable: $states"

    local entry h enabled timeout
    for entry in $before; do
        IFS=: read -r h enabled timeout <<< "$entry"
        xe host-param-set uuid=$h ssh-enabled-timeout=$timeout   # first: enabling stamps the expiry from it
        [ "$enabled" = true ] && xe host-enable-ssh uuid=$h
    done
    echo "OK: manage-ssh-access"
}
```

<details><summary>Example output</summary>

```text
sdk-host1: ssh enabled=true, expires 20260101T10:00:00Z
sdk-host2: ssh enabled=true, expires 20260101T10:00:00Z
After disable: sdk-host1=false, sdk-host2=false
OK: manage-ssh-access
```

</details>

## Python

Source: [`python/hosts_and_pools/manage_ssh_access.py`](../../python/hosts_and_pools/manage_ssh_access.py)

```python
"""Manage SSH access.

Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it again
— the pool-level call fans out to every host.

Run it::

    manage_ssh_access("https://xenserver", "root", password)
"""

from connection import connect


def manage_ssh_access(url, username, password):
    """Turn the pool's SSH service on with an automatic cut-off, read it back, then turn it off.

    Timed access is the point: set the timeout first and the server stamps an ssh_expiry when SSH
    is enabled, so a window opened for troubleshooting closes itself. pool.set_ssh_enabled_timeout
    is itself a pool-wide fan-out call, exactly like enable_ssh/disable_ssh - no need to loop
    hosts for it either."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = list(x.pool.get_all())[0]
    # Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
    before = {h: (r["ssh_enabled"], r["ssh_enabled_timeout"]) for h, r in x.host.get_all_records().items()}

    x.pool.set_ssh_enabled_timeout(pool, str(3600))   # one hour

    # The pool call fans out to every host, so there is no need to loop for the enable itself.
    x.pool.enable_ssh(pool)
    for host in x.host.get_all():
        record = x.host.get_record(host)
        print("%s: ssh enabled=%s, expires %s"
              % (record["name_label"], record["ssh_enabled"], record["ssh_expiry"]))

    x.pool.disable_ssh(pool)
    print("After disable: %s"
          % ", ".join("%s=%s" % (h["name_label"], h["ssh_enabled"])
                      for h in x.host.get_all_records().values()))

    for host, (enabled, timeout) in before.items():
        x.host.set_ssh_enabled_timeout(host, timeout)   # first: enabling stamps the expiry from it
        if enabled:
            x.host.enable_ssh(host)
    print("OK: manage-ssh-access")
    session.logout()
```

<details><summary>Example output</summary>

```text
sdk-host1: ssh enabled=True, expires 20260101T09:00:00Z
sdk-host2: ssh enabled=True, expires 20260101T09:00:00Z
After disable: sdk-host1=False, sdk-host2=False
OK: manage-ssh-access
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/ManageSshAccess.cs`](../../csharp/HostsAndPools/ManageSshAccess.cs)

```csharp
/// <summary>
/// Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it again —
/// the pool-level call fans out to every host.
/// </summary>
/// <example>
/// <code>
/// Workflows.ManageSshAccess("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ManageSshAccess(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0];
    // Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
    var before = Host.get_all_records(session)
        .ToDictionary(kv => kv.Key.opaque_ref, kv => (kv.Value.ssh_enabled, kv.Value.ssh_enabled_timeout));

    // Timed access is the point: set the timeout first and the server stamps an ssh_expiry when SSH
    // is enabled, so a window opened for troubleshooting closes itself. set_ssh_enabled_timeout is
    // itself a pool-wide fan-out call, exactly like enable_ssh/disable_ssh - no need to loop hosts.
    Pool.set_ssh_enabled_timeout(session, pool.opaque_ref, 3600);

    // The pool call fans out to every host, so there is no need to loop for the enable itself.
    Pool.enable_ssh(session, pool.opaque_ref);
    foreach (var record in Host.get_all_records(session).Values)
        Console.WriteLine($"{record.name_label}: ssh enabled={record.ssh_enabled}, "
                          + $"expires {record.ssh_expiry:u}");

    Pool.disable_ssh(session, pool.opaque_ref);
    Console.WriteLine("After disable: " + string.Join(", ",
        Host.get_all_records(session).Values.Select(h => $"{h.name_label}={h.ssh_enabled}")));

    foreach (var (host, (enabled, timeout)) in before)
    {
        Host.set_ssh_enabled_timeout(session, host, timeout);   // first: enabling stamps the expiry from it
        if (enabled) Host.enable_ssh(session, host);
    }
    Console.WriteLine("OK: manage-ssh-access");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
sdk-host1: ssh enabled=True, expires 2026-01-01 09:00:00Z
sdk-host2: ssh enabled=True, expires 2026-01-01 09:00:00Z
After disable: sdk-host1=False, sdk-host2=False
OK: manage-ssh-access
```

</details>

## Go

Source: [`go/manage_ssh_access.go`](../../go/manage_ssh_access.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// manageSSHAccess - Manage SSH access.
//
// Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it
// again — the pool-level call fans out to every host.
func manageSSHAccess(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	// Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
	before, err := xenapi.Host.GetAllRecords(session)
	check(err)

	// Timed access is the point: set the timeout first and the server stamps an expiry when SSH is
	// enabled, so a window opened for troubleshooting closes itself. This is itself a pool-wide
	// fan-out call, exactly like EnableSSH/DisableSSH - no need to loop hosts for it either.
	check(xenapi.Pool.SetSSHEnabledTimeout(session, pools[0], 3600))

	// The pool call fans out to every host, so there is no need to loop for the enable itself.
	check(xenapi.Pool.EnableSSH(session, pools[0]))
	for _, host := range hosts {
		record, err := xenapi.Host.GetRecord(session, host)
		check(err)
		fmt.Printf("%s: ssh enabled=%t, expires %s\n", record.NameLabel, record.SSHEnabled,
			record.SSHExpiry.UTC().Format("20060102T15:04:05Z"))
	}

	check(xenapi.Pool.DisableSSH(session, pools[0]))
	states := []string{}
	for _, host := range hosts {
		record, err := xenapi.Host.GetRecord(session, host)
		check(err)
		states = append(states, fmt.Sprintf("%s=%t", record.NameLabel, record.SSHEnabled))
	}
	fmt.Printf("After disable: %s\n", strings.Join(states, ", "))

	for host, record := range before {
		// first: enabling stamps the expiry from it
		check(xenapi.Host.SetSSHEnabledTimeout(session, host, record.SSHEnabledTimeout))
		if record.SSHEnabled {
			check(xenapi.Host.EnableSSH(session, host))
		}
	}
	fmt.Println("OK: manage-ssh-access")
}
```

<details><summary>Example output</summary>

```text
sdk-host1: ssh enabled=true, expires 20260101T09:00:00Z
sdk-host2: ssh enabled=true, expires 20260101T09:00:00Z
After disable: sdk-host1=false, sdk-host2=false
OK: manage-ssh-access
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ManageSshAccess.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ManageSshAccess.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageSshAccess {
    private ManageSshAccess() {
    }

    /**
     * Manage SSH access.
     *
     * <p>Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it
     * again — the pool-level call fans out to every host.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageSshAccess.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Pool pool = Pool.getAll(conn).iterator().next();
            // Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
            Map<Host, Host.Record> before = Host.getAllRecords(conn);

            // Timed access is the point: set the timeout first and the server stamps an expiry when SSH
            // is enabled, so a window opened for troubleshooting closes itself. set_ssh_enabled_timeout is
            // itself a pool-wide fan-out call, exactly like enable_ssh/disable_ssh - no need to loop hosts.
            pool.setSshEnabledTimeout(conn, 3600L);

            // The pool call fans out to every host, so there is no need to loop for the enable itself.
            pool.enableSsh(conn);
            for (Host.Record record : Host.getAllRecords(conn).values())
                System.out.printf("%s: ssh enabled=%b, expires %tFT%<tTZ%n",
                    record.nameLabel, record.sshEnabled, record.sshExpiry);

            pool.disableSsh(conn);
            StringBuilder after = new StringBuilder();
            for (Host.Record record : Host.getAllRecords(conn).values()) {
                if (after.length() > 0) after.append(", ");
                after.append(record.nameLabel).append("=").append(record.sshEnabled);
            }
            System.out.println("After disable: " + after);

            for (Map.Entry<Host, Host.Record> e : before.entrySet()) {
                // first: enabling stamps the expiry from it
                e.getKey().setSshEnabledTimeout(conn, e.getValue().sshEnabledTimeout);
                if (e.getValue().sshEnabled) e.getKey().enableSsh(conn);
            }
            System.out.println("OK: manage-ssh-access");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
sdk-host1: ssh enabled=true, expires 2026-01-01T09:00:00Z
sdk-host2: ssh enabled=true, expires 2026-01-01T09:00:00Z
After disable: sdk-host1=false, sdk-host2=false
OK: manage-ssh-access
```

</details>
