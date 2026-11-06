<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage pool membership

List the pool's member hosts and which one coordinates it, promote a different host to coordinator, then promote the original back.

**Caution:** hands the coordinator role to another host and back, which restarts the toolstack on every host and briefly drops every management connection.

Workflow `manage-pool-membership`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ManagePoolMembership.ps1`](../../powershell/HostsAndPools/Invoke-ManagePoolMembership.ps1)

```powershell
function Invoke-ManagePoolMembership {
    <#
    .SYNOPSIS
        Manage pool membership.
    .DESCRIPTION
        List the pool's member hosts and which one coordinates it, promote a different host to coordinator,
        then promote the original back.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    $hosts = Get-XenHost
    $originalRef = $pool.master.opaque_ref
    $original = $hosts | Where-Object { $_.opaque_ref -eq $originalRef }
    Write-Host "Coordinator: $($original.name_label)"
    foreach ($h in $hosts) {
        $tag = if ($h.opaque_ref -eq $originalRef) { " (coordinator)" } else { "" }
        Write-Host "  member: $($h.name_label)$tag"
    }

    # Promote another member. The pool database moves with the role and clients are redirected, so this
    # briefly interrupts management traffic — it does not move any VM.
    $other = $hosts | Where-Object { $_.opaque_ref -ne $originalRef } | Select-Object -First 1
    Invoke-XenPool -Ref $pool.opaque_ref -XenAction DesignateNewMaster -XenHost $other.opaque_ref
    Write-Host "Promoting:   $($other.name_label) (xapi restarts pool-wide; reconnecting)"

    $session = Reconnect-AfterMasterChange -Url $Url -UserName $UserName -Password $Password `
        -NewMasterUuid $other.uuid
    $pool = Get-XenPool | Select-Object -First 1
    Write-Host "Promoted:    $((Get-XenHost -Ref $pool.master.opaque_ref).name_label)"

    # Put it back. Ejecting a member (Pool.eject) is the other half of this surface and is deliberately
    # not shown: it cannot be undone from the pool, because rejoining is initiated by the ejected host.
    Invoke-XenPool -Ref $pool.opaque_ref -XenAction DesignateNewMaster -XenHost $originalRef
    Write-Host "Restoring:   $($original.name_label) (reconnecting again)"

    $session = Reconnect-AfterMasterChange -Url $Url -UserName $UserName -Password $Password `
        -NewMasterUuid $original.uuid
    $pool = Get-XenPool | Select-Object -First 1
    Write-Host "Restored:    $((Get-XenHost -Ref $pool.master.opaque_ref).name_label)"

    Write-Host "OK: manage-pool-membership"
    $session | Disconnect-XenServer
}

function Reconnect-AfterMasterChange {
    <#
    .SYNOPSIS
        Wait out a pool-wide xapi restart (pool.designate_new_master) and reconnect.
    .DESCRIPTION
        designate_new_master returns BEFORE the change: for a while the old coordinator still answers, and
        still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not enough
        - keep reconnecting until the pool names the new coordinator (by uuid; Connect-Example follows
        HOST_IS_SLAVE to wherever the coordinator now is). That can take minutes.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$NewMasterUuid,
        [int]$TimeoutSeconds = 600,
        [int]$IntervalSeconds = 5
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
            $master = (Get-XenPool | Select-Object -First 1).master
            # The new coordinator answers before the pool has settled - calls made too soon fail
            # (HANDLE_INVALID on the operation's own task) - so also wait for every host to be back,
            # live and enabled.
            $settled = (Get-XenHost -Ref $master.opaque_ref).uuid -eq $NewMasterUuid -and
                -not (Get-XenHost | Where-Object {
                    -not $_.enabled -or -not (Get-XenHostMetrics -Ref $_.metrics.opaque_ref).live
                })
            if ($settled) { return $session }
            $session | Disconnect-XenServer
            $lastError = "the pool has not settled under the new coordinator"
        }
        catch { $lastError = $_ }
        Start-Sleep -Seconds $IntervalSeconds
    }
    throw "the pool did not come back after the master change: $lastError"
}
```

<details><summary>Example output</summary>

```text
Coordinator: sdk-host1
  member: sdk-host1 (coordinator)
  member: sdk-host2
Promoting:   sdk-host2 (xapi restarts pool-wide; reconnecting)
Promoted:    sdk-host2
Restoring:   sdk-host1 (reconnecting again)
Restored:    sdk-host1
OK: manage-pool-membership
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/manage-pool-membership.sh`](../../cli/hosts-and-pools/manage-pool-membership.sh)

```bash
# Manage pool membership.
#
# List the pool's member hosts and which one coordinates it, promote a different host to coordinator, then
# promote the original back.
#
# Run it:
#   ./workflows.sh manage-pool-membership https://xenserver root "$password"

manage_pool_membership() {
    local original other
    original=$(xe pool-list params=master --minimal)
    echo "Coordinator: $(xe host-list uuid="$original" params=name-label --minimal)"
    for h in $(each_csv "$(xe host-list --minimal)"); do
        if [ "$h" = "$original" ]; then
            echo "  member: $(xe host-list uuid="$h" params=name-label --minimal) (coordinator)"
        else
            echo "  member: $(xe host-list uuid="$h" params=name-label --minimal)"
            other=$h
        fi
    done

    # Promote another member. The pool database moves with the role and clients are redirected, so this
    # briefly interrupts management traffic - it does not move any VM. pool-designate-new-master restarts
    # xapi pool-wide, so the connection this script is using does not survive it: reconnect (a bounded
    # wait/retry) before touching the pool again, rather than assuming the next xe call will just work.
    # Names first: once the switch starts, the address this script talks to may already be a supporter.
    local other_name original_name
    other_name=$(xe host-list uuid="$other" params=name-label --minimal)
    original_name=$(xe host-list uuid="$original" params=name-label --minimal)
    xe pool-designate-new-master host-uuid="$other"
    echo "Promoting:   $other_name (xapi restarts pool-wide; reconnecting)"
    reconnect_after_master_change "$other"
    echo "Promoted:    $other_name"

    # Put it back. Ejecting a member (pool-eject) is the other half of this surface and is deliberately
    # not shown: it cannot be undone from the pool, because rejoining is initiated by the ejected host.
    xe pool-designate-new-master host-uuid="$original"
    echo "Restoring:   $original_name (reconnecting again)"
    reconnect_after_master_change "$original"
    echo "Restored:    $original_name"
    echo "OK: manage-pool-membership"
}

# Wait out a pool-wide xapi restart (pool-designate-new-master) and find the new coordinator's address,
# updating $host - xe does not follow HOST_IS_SLAVE itself (see the probe at the top of this script).
#
# pool-designate-new-master returns BEFORE the change: for a while the old coordinator still answers, and
# still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not enough -
# keep reconnecting until the pool names the new coordinator (by uuid) AND every host is back, enabled and
# live. That can take minutes.
reconnect_after_master_change() {
    local new_master_uuid=$1 timeout=600 interval=5 probe
    local deadline=$((SECONDS + timeout))
    while [ $SECONDS -lt $deadline ]; do
        # Called as an if-condition, so set -e does not end the script when one of its xe calls fails -
        # and while xapi restarts across the pool, any of them can.
        if probe=$(xe pool-list --minimal 2>&1) && pool_settled_under "$new_master_uuid" "$probe"; then
            return 0
        fi
        if [[ $probe =~ (Master|Coordinator)\ IP\ address:\ ([0-9A-Fa-f.:]+) ]]; then
            host=${BASH_REMATCH[2]}
        fi
        sleep "$interval"
    done
    echo "the pool did not come back after the master change" >&2
    return 1
}

# True once the pool (uuid $2) names $1 as its coordinator AND every host is back, enabled and live. The
# new coordinator answers before the pool has settled - calls made too soon fail (HANDLE_INVALID on the
# operation's own task) - hence the second half.
pool_settled_under() {
    local master h
    master=$(xe pool-param-get uuid="$(first_csv "$2")" param-name=master) || return 1
    [ "$master" = "$1" ] || return 1
    for h in $(each_csv "$(xe host-list --minimal)"); do
        [ "$(xe host-param-get uuid=$h param-name=enabled)" = "true" ] || return 1
        [ "$(host_live "$h")" = "true" ] || return 1
    done
}
```

<details><summary>Example output</summary>

```text
Coordinator: sdk-host1
  member: sdk-host1 (coordinator)
  member: sdk-host2
Promoting:   sdk-host2 (xapi restarts pool-wide; reconnecting)
Promoted:    sdk-host2
Restoring:   sdk-host1 (reconnecting again)
Restored:    sdk-host1
OK: manage-pool-membership
```

</details>

## Python

Source: [`python/hosts_and_pools/manage_pool_membership.py`](../../python/hosts_and_pools/manage_pool_membership.py)

```python
"""Manage pool membership.

List the pool's member hosts and which one coordinates it, promote a different host to coordinator,
then promote the original back.

Run it::

    manage_pool_membership("https://xenserver", "root", password)
"""

import time

from connection import connect


def manage_pool_membership(url, username, password):
    """List the pool's hosts, promote a different coordinator, then promote the original back.

    designate_new_master runs a two-phase commit across every host and ends by restarting xapi
    pool-wide (the new coordinator becomes master, every other host becomes its slave) - so the
    session this call was made on, and the connection itself, do not survive it. Reconnect (with a
    bounded wait, since xapi is briefly unavailable while it restarts) before touching the pool
    again, rather than assuming the session is still good."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    hosts = x.host.get_all_records()
    original = x.pool.get_master(pool)
    print(f"Coordinator: {hosts[original]['name_label']}")
    for ref, host in hosts.items():
        print(f"  member: {host['name_label']}" + (" (coordinator)" if ref == original else ""))

    # Promote another member. The pool database moves with the role and clients are redirected, so this
    # briefly interrupts management traffic — it does not move any VM.
    other = next(ref for ref in hosts if ref != original)
    x.pool.designate_new_master(other)
    print(f"Promoting:   {hosts[other]['name_label']} (xapi restarts pool-wide; reconnecting)")

    session = _reconnect_after_master_change(url, username, password, hosts[other]["uuid"])
    x = session.xenapi
    pool = x.pool.get_all()[0]
    print(f"Promoted:    {x.host.get_name_label(x.pool.get_master(pool))}")

    # Put it back. Ejecting a member (pool.eject) is the other half of this surface and is deliberately
    # not shown: it cannot be undone from the pool, because rejoining is initiated by the ejected host.
    x.pool.designate_new_master(original)
    print(f"Restoring:   {hosts[original]['name_label']} (reconnecting again)")

    session = _reconnect_after_master_change(url, username, password, hosts[original]["uuid"])
    x = session.xenapi
    pool = x.pool.get_all()[0]
    print(f"Restored:    {x.host.get_name_label(x.pool.get_master(pool))}")

    print("OK: manage-pool-membership")
    x.session.logout()


def _reconnect_after_master_change(url, username, password, new_master_uuid, timeout=600, interval=5):
    """Wait out a pool-wide xapi restart (pool.designate_new_master) and reconnect.

    designate_new_master returns BEFORE the change: for a while the old coordinator still answers,
    and still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not
    enough - keep reconnecting until the pool names the new coordinator (by uuid; connect() follows
    HOST_IS_SLAVE to wherever the coordinator now is). That can take minutes."""
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            session = connect(url, username, password)
            x = session.xenapi
            master = x.pool.get_master(x.pool.get_all()[0])
            # The new coordinator answers before the pool has settled - calls made too soon fail
            # (HANDLE_INVALID on the operation's own task) - so also wait for every host to be back,
            # live and enabled.
            if x.host.get_uuid(master) == new_master_uuid and all(
                    r["enabled"] and x.host_metrics.get_live(r["metrics"])
                    for r in x.host.get_all_records().values()):
                return session
            x.session.logout()
            last_error = "the pool has not settled under the new coordinator"
        except Exception as e:
            last_error = e
        time.sleep(interval)
    raise RuntimeError("the pool did not come back after the master change: %s" % last_error)
```

<details><summary>Example output</summary>

```text
Coordinator: sdk-host1
  member: sdk-host1 (coordinator)
  member: sdk-host2
Promoting:   sdk-host2 (xapi restarts pool-wide; reconnecting)
Promoted:    sdk-host2
Restoring:   sdk-host1 (reconnecting again)
Restored:    sdk-host1
OK: manage-pool-membership
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/ManagePoolMembership.cs`](../../csharp/HostsAndPools/ManagePoolMembership.cs)

```csharp
/// <summary>
/// List the pool's member hosts and which one coordinates it, promote a different host to coordinator,
/// then promote the original back.
/// </summary>
/// <example>
/// <code>
/// Workflows.ManagePoolMembership("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ManagePoolMembership(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var poolRef = Pool.get_all(session)[0].opaque_ref;

    var hosts = Host.get_all_records(session);
    var original = Pool.get_master(session, poolRef).opaque_ref;
    Console.WriteLine($"Coordinator: {hosts[new XenRef<Host>(original)].name_label}");
    foreach (var h in hosts)
        Console.WriteLine($"  member: {h.Value.name_label}{(h.Key.opaque_ref == original ? " (coordinator)" : "")}");

    // Promote another member. The pool database moves with the role and clients are redirected, so
    // this briefly interrupts management traffic — it does not move any VM.
    var other = hosts.Keys.First(k => k.opaque_ref != original).opaque_ref;
    Pool.designate_new_master(session, other);
    Console.WriteLine($"Promoting:   {hosts[new XenRef<Host>(other)].name_label} " +
                      "(xapi restarts pool-wide; reconnecting)");

    // designate_new_master runs a two-phase commit across every host and ends by restarting xapi
    // pool-wide - the session this call was made on, and the connection itself, do not survive it.
    // Reconnect (with a bounded wait) before touching the pool again, and re-resolve every ref from
    // the fresh session rather than assuming the old ones are still good.
    session = ReconnectAfterMasterChange(url, user, password, hosts[new XenRef<Host>(other)].uuid);
    poolRef = Pool.get_all(session)[0].opaque_ref;
    Console.WriteLine($"Promoted:    {Host.get_name_label(session, Pool.get_master(session, poolRef).opaque_ref)}");

    // Put it back. Ejecting a member (Pool.eject) is the other half of this surface and is
    // deliberately not shown: it cannot be undone from the pool, because rejoining is initiated by
    // the ejected host.
    Pool.designate_new_master(session, original);
    Console.WriteLine($"Restoring:   {hosts[new XenRef<Host>(original)].name_label} (reconnecting again)");

    session = ReconnectAfterMasterChange(url, user, password, hosts[new XenRef<Host>(original)].uuid);
    poolRef = Pool.get_all(session)[0].opaque_ref;
    Console.WriteLine($"Restored:    {Host.get_name_label(session, Pool.get_master(session, poolRef).opaque_ref)}");

    Console.WriteLine("OK: manage-pool-membership");
    session.logout();
}

/// <summary>
/// Wait out a pool-wide xapi restart (Pool.designate_new_master) and reconnect.
///
/// designate_new_master returns BEFORE the change: for a while the old coordinator still answers,
/// and still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not
/// enough - keep reconnecting until the pool names the new coordinator (by uuid; Connect follows
/// HOST_IS_SLAVE to wherever the coordinator now is). That can take minutes. </summary>
private static Session ReconnectAfterMasterChange(string url, string user, string password,
    string newMasterUuid, int timeoutSeconds = 600, int intervalSeconds = 5)
{
    var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
    object lastError = null;
    while (DateTime.UtcNow < deadline)
    {
        try
        {
            var session = Connect(url, user, password);
            var master = Pool.get_master(session, Pool.get_all(session)[0].opaque_ref).opaque_ref;
            // The new coordinator answers before the pool has settled - calls made too soon fail
            // (HANDLE_INVALID on the operation's own task) - so also wait for every host to be back,
            // live and enabled.
            if (Host.get_uuid(session, master) == newMasterUuid && Host.get_all_records(session).Values.All(
                    r => r.enabled && Host_metrics.get_live(session, r.metrics.opaque_ref)))
                return session;
            session.logout();
            lastError = "the pool has not settled under the new coordinator";
        }
        catch (Exception e)
        {
            lastError = e;
        }
        System.Threading.Thread.Sleep(intervalSeconds * 1000);
    }
    throw new Exception($"the pool did not come back after the master change: {lastError}");
}
```

<details><summary>Example output</summary>

```text
Coordinator: sdk-host1
  member: sdk-host1 (coordinator)
  member: sdk-host2
Promoting:   sdk-host2 (xapi restarts pool-wide; reconnecting)
Promoted:    sdk-host2
Restoring:   sdk-host1 (reconnecting again)
Restored:    sdk-host1
OK: manage-pool-membership
```

</details>

## Go

Source: [`go/manage_pool_membership.go`](../../go/manage_pool_membership.go)

```go
package main

import (
	"fmt"
	"time"

	"go/xenapi"
)

// managePoolMembership lists the pool's hosts, promotes a different coordinator, then promotes
// the original back. designate_new_master runs a two-phase commit across every host and ends by
// restarting xapi pool-wide (the new coordinator becomes master, every other host becomes its
// slave) - so the session this call was made on, and the connection itself, do not survive it.
// Reconnect (with a bounded wait) before touching the pool again, rather than assuming the session
// is still good, and re-resolve pool/host refs from the fresh session each time.
func managePoolMembership(url, user, password string) {
	session := connect(url, user, password)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)

	original, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	name, _ := xenapi.Host.GetNameLabel(session, original)
	fmt.Printf("Coordinator: %s\n", name)

	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	var other xenapi.HostRef
	for _, h := range hosts {
		hn, _ := xenapi.Host.GetNameLabel(session, h)
		suffix := ""
		if h == original {
			suffix = " (coordinator)"
		} else {
			other = h
		}
		fmt.Printf("  member: %s%s\n", hn, suffix)
	}
	otherName, _ := xenapi.Host.GetNameLabel(session, other)
	otherUUID, _ := xenapi.Host.GetUUID(session, other)
	originalUUID, _ := xenapi.Host.GetUUID(session, original)

	// Promote another member. The pool database moves with the role and clients are redirected, so this
	// briefly interrupts management traffic — it does not move any VM.
	check(xenapi.Pool.DesignateNewMaster(session, other))
	fmt.Printf("Promoting:   %s (xapi restarts pool-wide; reconnecting)\n", otherName)

	session = reconnectAfterMasterChange(url, user, password, otherUUID)
	pools, err = xenapi.Pool.GetAll(session)
	check(err)
	master, _ := xenapi.Pool.GetMaster(session, pools[0])
	masterName, _ := xenapi.Host.GetNameLabel(session, master)
	fmt.Printf("Promoted:    %s\n", masterName)

	// Put it back. Ejecting a member (Pool.Eject) is the other half of this surface and is deliberately
	// not shown: it cannot be undone from the pool, because rejoining is initiated by the ejected host.
	check(xenapi.Pool.DesignateNewMaster(session, original))
	fmt.Printf("Restoring:   %s (reconnecting again)\n", name)

	session = reconnectAfterMasterChange(url, user, password, originalUUID)
	pools, err = xenapi.Pool.GetAll(session)
	check(err)
	master, _ = xenapi.Pool.GetMaster(session, pools[0])
	masterName, _ = xenapi.Host.GetNameLabel(session, master)
	fmt.Printf("Restored:    %s\n", masterName)

	fmt.Println("OK: manage-pool-membership")
	session.Logout()
}

// reconnectAfterMasterChange waits out a pool-wide xapi restart (pool.DesignateNewMaster) and
// reconnects.
//
// DesignateNewMaster returns BEFORE the change: for a while the old coordinator still answers, and
// still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not
// enough - keep reconnecting until the pool names the new coordinator (by uuid; connect follows
// HOST_IS_SLAVE to wherever the coordinator now is). That can take minutes.
func reconnectAfterMasterChange(url, user, password, newMasterUUID string) (session *xenapi.Session) {
	deadline := time.Now().Add(600 * time.Second)
	var lastErr any
	for time.Now().Before(deadline) {
		settled := func() (ok bool) {
			defer func() {
				if r := recover(); r != nil {
					lastErr = r
					ok = false
				}
			}()
			session = connect(url, user, password)
			pools, err := xenapi.Pool.GetAll(session)
			check(err)
			master, err := xenapi.Pool.GetMaster(session, pools[0])
			check(err)
			uuid, err := xenapi.Host.GetUUID(session, master)
			check(err)
			// The new coordinator answers before the pool has settled - calls made too soon fail
			// (HANDLE_INVALID on the operation's own task) - so also wait for every host to be back,
			// live and enabled.
			if uuid != newMasterUUID {
				lastErr = "the pool has not settled under the new coordinator"
				return false
			}
			hosts, err := xenapi.Host.GetAllRecords(session)
			check(err)
			for _, h := range hosts {
				live, err := xenapi.HostMetrics.GetLive(session, h.Metrics)
				check(err)
				if !h.Enabled || !live {
					lastErr = "the pool has not settled under the new coordinator"
					return false
				}
			}
			return true
		}()
		if settled {
			return session
		}
		if session != nil {
			session.Logout()
		}
		time.Sleep(5 * time.Second)
	}
	panic(fmt.Sprintf("the pool did not come back after the master change: %v", lastErr))
}
```

<details><summary>Example output</summary>

```text
Coordinator: sdk-host1
  member: sdk-host1 (coordinator)
  member: sdk-host2
Promoting:   sdk-host2 (xapi restarts pool-wide; reconnecting)
Promoted:    sdk-host2
Restoring:   sdk-host1 (reconnecting again)
Restored:    sdk-host1
OK: manage-pool-membership
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ManagePoolMembership.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ManagePoolMembership.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import com.xenserver.samples.PoolConnection.CoordinatorUnknown;

import java.util.Map;

import static com.xenserver.samples.Helpers.hostUrl;
import static com.xenserver.samples.PoolConnection.connect;

public final class ManagePoolMembership {
    private ManagePoolMembership() {
    }

    /**
     * Manage pool membership.
     *
     * <p>List the pool's member hosts and which one coordinates it, promote a different host to
     * coordinator, then promote the original back.
     *
     * <p>designateNewMaster runs a two-phase commit across every host and ends by restarting xapi
     * pool-wide (the new coordinator becomes master, every other host becomes its slave) - so the session
     * this call was made on, and the connection itself, do not survive it. Reconnect (with a bounded wait,
     * since xapi is briefly unavailable while it restarts) before touching the pool again, and re-resolve
     * every ref from the fresh session - do not reuse the old session or any ref resolved from it.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        Host original = pool.getMaster(conn);
        String originalName = original.getNameLabel(conn);
        String originalUuid = original.getUuid(conn);
        System.out.println("Coordinator: " + originalName);

        String otherName = null;
        for (Host h : Host.getAll(conn)) {
            System.out.println("  member: " + h.getNameLabel(conn)
                    + (h.equals(original) ? " (coordinator)" : ""));
            if (!h.equals(original)) otherName = h.getNameLabel(conn);
        }
        Host other = hostByName(conn, otherName);
        String otherUuid = other.getUuid(conn);
        // Each new coordinator's own address, to reconnect to if following HOST_IS_SLAVE from the old one
        // fails: Java SDKs up to 26.22 read HostIsSlave.masterIPAddress as "" under JSON-RPC.
        String otherUrl = hostUrl(url, other.getAddress(conn));
        String originalUrl = hostUrl(url, original.getAddress(conn));

        // Promote another member. The pool database moves with the role and clients are redirected, so
        // this briefly interrupts management traffic - it does not move any VM.
        Pool.designateNewMaster(conn, other);
        System.out.println("Promoting:   " + otherName + " (xapi restarts pool-wide; reconnecting)");

        conn = reconnectAfterMasterChange(url, otherUrl, user, password, otherUuid);
        pool = Pool.getAll(conn).iterator().next();
        System.out.println("Promoted:    " + pool.getMaster(conn).getNameLabel(conn));

        // Put it back. Ejecting a member (Pool.eject) is the other half of this surface and is
        // deliberately not shown: it cannot be undone from the pool, because rejoining is initiated
        // by the ejected host.
        Host originalAgain = hostByName(conn, originalName);
        Pool.designateNewMaster(conn, originalAgain);
        System.out.println("Restoring:   " + originalName + " (reconnecting again)");

        conn = reconnectAfterMasterChange(url, originalUrl, user, password, originalUuid);
        pool = Pool.getAll(conn).iterator().next();
        System.out.println("Restored:    " + pool.getMaster(conn).getNameLabel(conn));

        System.out.println("OK: manage-pool-membership");
        Session.logout(conn);
    }

    /**
     * Wait out a pool-wide xapi restart (pool.designateNewMaster) and reconnect.
     *
     * <p>designateNewMaster returns BEFORE the change: for a while the old coordinator still answers, and
     * still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not enough
     * - keep reconnecting until the pool names the new coordinator (by uuid; connect() follows
     * HOST_IS_SLAVE to wherever the coordinator now is). That can take minutes.
     */
    private static Connection reconnectAfterMasterChange(String url, String newMasterUrl, String user,
            String password, String newMasterUuid) throws Exception {
        long deadline = System.currentTimeMillis() + 600_000;
        Object lastError = null;
        while (System.currentTimeMillis() < deadline) {
            try {
                Connection conn;
                try {
                    conn = connect(url, user, password);
                } catch (CoordinatorUnknown e) {
                    conn = connect(newMasterUrl, user, password);
                }
                Host master = Pool.getAll(conn).iterator().next().getMaster(conn);
                // The new coordinator answers before the pool has settled - calls made too soon fail
                // (HANDLE_INVALID on the operation's own task) - so also wait for every host to be back,
                // live and enabled.
                boolean settled = master.getUuid(conn).equals(newMasterUuid);
                if (settled) {
                    for (Map.Entry<Host, Host.Record> e : Host.getAllRecords(conn).entrySet()) {
                        if (!e.getValue().enabled || !e.getValue().metrics.getLive(conn)) {
                            settled = false;
                            break;
                        }
                    }
                }
                if (settled) return conn;
                Session.logout(conn);
                lastError = "the pool has not settled under the new coordinator";
            } catch (Exception e) {
                lastError = e;
            }
            Thread.sleep(5000);
        }
        throw new RuntimeException("the pool did not come back after the master change: " + lastError);
    }

    /**
     * Find a host by its exact name label (used to re-resolve a host across a reconnect).
     */
    private static Host hostByName(Connection conn, String name) throws Exception {
        for (Map.Entry<Host, Host.Record> e : Host.getAllRecords(conn).entrySet())
            if (name.equals(e.getValue().nameLabel)) return e.getKey();
        throw new RuntimeException("no host named '" + name + "' was found");
    }
}
```

<details><summary>Example output</summary>

```text
Coordinator: sdk-host1
  member: sdk-host2
  member: sdk-host1 (coordinator)
Promoting:   sdk-host2 (xapi restarts pool-wide; reconnecting)
Promoted:    sdk-host2
Restoring:   sdk-host1 (reconnecting again)
Restored:    sdk-host1
OK: manage-pool-membership
```

</details>
