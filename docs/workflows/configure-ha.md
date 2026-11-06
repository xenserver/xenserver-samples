<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure high availability

Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many host failures the pool can tolerate, enable HA, then disable it again.

**Caution:** while HA is on, it can restart hosts it considers failed.

Workflow `configure-ha`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ConfigureHa.ps1`](../../powershell/HostsAndPools/Invoke-ConfigureHa.ps1)

```powershell
function Invoke-ConfigureHa {
    <#
    .SYNOPSIS
        Configure high availability.
    .DESCRIPTION
        Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many host
        failures the pool can tolerate, enable HA, then disable it again.
    .EXAMPLE
        Invoke-ConfigureHa -Url https://xenserver -UserName root -Password $password -HeartbeatSrName 'Shared NFS'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$HeartbeatSrName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    # The HA heartbeat statefile needs a shared SR. Confirm the chosen SR can host it.
    $sr = Get-XenSR -Name $HeartbeatSrName | Where-Object { $_.shared } | Select-Object -First 1
    if (-not $sr) { throw "No shared SR named '$HeartbeatSrName' was found." }
    Write-Host "Heartbeat SR:  $($sr.name_label)"
    $sr | Invoke-XenSR -XenAction AssertCanHostHaStatefile

    # What HA does per VM. The restart priority decides which guests come back first after a host
    # failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
    $guest = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot
    } | Select-Object -First 1

    # How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those: a target
    # computed with none protected can be too high, and protecting a VM afterwards then fails
    # HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN. The configuration maps VM references (XenRef objects - a ref
    # string fails to cast) to restart priorities.
    $guestRef = [XenAPI.XenRef[XenAPI.VM]]::Create($guest.opaque_ref)
    $ntol = $pool | Invoke-XenPool -XenAction HaComputeHypotheticalMaxHostFailuresToTolerate `
        -Configuration @{ $guestRef = "restart" } -PassThru
    Write-Host "Max failures:  $ntol"
    $pool | Set-XenPool -HaHostFailuresToTolerate $ntol

    $pool | Invoke-XenPool -XenAction EnableHa -HeartbeatSrs @($sr) -Configuration @{}
    try {
        Write-Host "HA enabled:    $((Get-XenPool | Select-Object -First 1).ha_enabled)"

        $was = $guest.ha_restart_priority
        $guest | Set-XenVM -HaRestartPriority "restart"
        $nowPriority = (Get-XenVM -Ref $guest.opaque_ref).ha_restart_priority
        Write-Host "$($guest.name_label) priority: '$was' -> '$nowPriority'"
        $guest | Set-XenVM -HaRestartPriority $was

        # And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
        # failure HA should undo, or an administrator's intent it should respect?
        $internal = (Get-XenPool -Ref $pool.opaque_ref).ha_reboot_vm_on_internal_shutdown
        Write-Host "Restart on internal shutdown: $internal"
    }
    finally {
        # Turn HA back off however the above went: left on, it blocks host reboots, coordinator
        # changes and more (HA_IS_ENABLED, HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN).
        $pool | Invoke-XenPool -XenAction DisableHa
    }
    Write-Host "HA enabled:    $((Get-XenPool | Select-Object -First 1).ha_enabled)"
    Write-Host "OK: configure-ha"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Heartbeat SR:  Shared NFS
Max failures:  1
HA enabled:    True
web-01 priority: '' -> 'restart'
Restart on internal shutdown: True
HA enabled:    False
OK: configure-ha
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/configure-ha.sh`](../../cli/hosts-and-pools/configure-ha.sh)

```bash
# Configure high availability.
#
# Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many host
# failures the pool can tolerate, enable HA, then disable it again.
#
# Run it:
#   ./workflows.sh configure-ha https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   heartbeat_sr_name (Shared NFS)

configure_ha() {
    pool=$(xe pool-list --minimal)
    # xe has no command to check in advance that the chosen SR can host the HA heartbeat statefile
    # (the SDK's SR.assert_can_host_ha_statefile); pool-ha-enable below fails on its own if it can't.

    # What HA does per VM. The restart priority decides which guests come back first after a host
    # failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
    guest=$(first_csv "$(xe vm-list is-a-template=false is-control-domain=false is-a-snapshot=false --minimal)")

    # How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those: a target
    # computed with none protected can be too high, and protecting a VM afterwards then fails
    # HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN.
    ntol=$(xe pool-ha-compute-hypothetical-max-host-failures-to-tolerate vm-uuid=$guest restart-priority=restart)
    echo "Max failures: $ntol"
    xe pool-param-set uuid=$pool ha-host-failures-to-tolerate=$ntol

    xe pool-ha-enable heartbeat-sr-uuids=$(sr_by_name "$(param heartbeat_sr_name "Shared NFS")")
    echo "HA enabled: $(xe pool-param-get uuid=$pool param-name=ha-enabled)"

    was=$(xe vm-param-get uuid=$guest param-name=ha-restart-priority)
    xe vm-param-set uuid=$guest ha-restart-priority=restart
    echo "$(xe vm-param-get uuid=$guest param-name=name-label) priority: '$was' -> '$(xe vm-param-get uuid=$guest param-name=ha-restart-priority)'"
    xe vm-param-set uuid=$guest ha-restart-priority="$was"

    # And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
    # failure HA should undo, or an administrator's intent it should respect?
    echo "Restart on internal shutdown: $(xe pool-param-get uuid=$pool param-name=ha-reboot-vm-on-internal-shutdown)"

    xe pool-ha-disable
    echo "HA enabled: $(xe pool-param-get uuid=$pool param-name=ha-enabled)"
    echo "OK: configure-ha"
}
```

<details><summary>Example output</summary>

```text
Max failures: 1
HA enabled: true
web-01 priority: '' -> 'restart'
Restart on internal shutdown: true
HA enabled: false
OK: configure-ha
```

</details>

## Python

Source: [`python/hosts_and_pools/configure_ha.py`](../../python/hosts_and_pools/configure_ha.py)

```python
"""Configure high availability.

Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many host
failures the pool can tolerate, enable HA, then disable it again.

Run it::

    configure_ha("https://xenserver", "root", password, "Shared NFS")
"""

from connection import connect
from helpers import sr_by_name


def configure_ha(url, username, password, heartbeat_sr_name):
    """Enable pool HA on the named shared heartbeat SR, then disable it again."""
    session = connect(url, username, password)
    pool_ref = list(session.xenapi.pool.get_all_records().keys())[0]

    # The HA heartbeat statefile needs a shared SR; confirm the chosen one can host it.
    sr_ref = sr_by_name(session, heartbeat_sr_name, shared=True)
    print("Heartbeat SR:  %s" % session.xenapi.SR.get_name_label(sr_ref))
    session.xenapi.SR.assert_can_host_ha_statefile(sr_ref)

    # What HA does per VM. The restart priority decides which guests come back first after a host
    # failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
    guest = next(ref for ref, r in session.xenapi.VM.get_all_records().items()
                 if not r["is_a_template"] and not r["is_control_domain"] and not r["is_a_snapshot"])

    # How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those: a
    # target computed with none protected can be too high, and protecting a VM afterwards then fails
    # HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN.
    ntol = session.xenapi.pool.ha_compute_hypothetical_max_host_failures_to_tolerate({guest: "restart"})
    print("Max failures:  %s" % ntol)
    session.xenapi.pool.set_ha_host_failures_to_tolerate(pool_ref, ntol)
    session.xenapi.pool.enable_ha([sr_ref], {})
    try:
        print("HA enabled:    %s" % session.xenapi.pool.get_ha_enabled(pool_ref))

        was = session.xenapi.VM.get_ha_restart_priority(guest)
        session.xenapi.VM.set_ha_restart_priority(guest, "restart")
        print("%s priority: %r -> %r"
              % (session.xenapi.VM.get_name_label(guest), was,
                 session.xenapi.VM.get_ha_restart_priority(guest)))
        session.xenapi.VM.set_ha_restart_priority(guest, was)

        # And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
        # failure HA should undo, or an administrator's intent it should respect?
        internal = session.xenapi.pool.get_ha_reboot_vm_on_internal_shutdown(pool_ref)
        print("Restart on internal shutdown: %s" % internal)
    finally:
        # Turn HA back off however the above went: left on, it blocks host reboots, coordinator
        # changes and more (HA_IS_ENABLED, HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN).
        session.xenapi.pool.disable_ha()
    print("HA enabled:    %s" % session.xenapi.pool.get_ha_enabled(pool_ref))
    print("OK: configure-ha")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Heartbeat SR:  Shared NFS
Max failures:  1
HA enabled:    True
web-01 priority: '' -> 'restart'
Restart on internal shutdown: True
HA enabled:    False
OK: configure-ha
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/ConfigureHa.cs`](../../csharp/HostsAndPools/ConfigureHa.cs)

```csharp
/// <summary>
/// Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many host
/// failures the pool can tolerate, enable HA, then disable it again.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureHa("https://xenserver", "root", password, "Shared NFS");
/// </code>
/// </example>
public static void ConfigureHa(string url, string user, string password, string heartbeatSrName)
{
    var session = Connect(url, user, password);
    var poolRef = Pool.get_all_records(session).Keys.First().opaque_ref;

    // The HA heartbeat statefile needs a shared SR; confirm the chosen one can host it.
    var srRef = SrByName(session, heartbeatSrName, shared: true);
    Console.WriteLine($"Heartbeat SR:  {SR.get_name_label(session, srRef)}");
    SR.assert_can_host_ha_statefile(session, srRef);

    // What HA does per VM. The restart priority decides which guests come back first after a host
    // failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
    var guest = VM.get_all_records(session).First(kv =>
        !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot).Key.opaque_ref;

    // How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those: a
    // target computed with none protected can be too high, and protecting a VM afterwards then fails
    // HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN.
    var ntol = Pool.ha_compute_hypothetical_max_host_failures_to_tolerate(
        session, new Dictionary<XenRef<VM>, string> { { new XenRef<VM>(guest), "restart" } });
    Console.WriteLine($"Max failures:  {ntol}");
    Pool.set_ha_host_failures_to_tolerate(session, poolRef, ntol);
    Pool.enable_ha(session, new List<XenRef<SR>> { new(srRef) }, new Dictionary<string, string>());
    try
    {
        Console.WriteLine($"HA enabled:    {Pool.get_ha_enabled(session, poolRef)}");

        var wasPriority = VM.get_ha_restart_priority(session, guest);
        VM.set_ha_restart_priority(session, guest, "restart");
        Console.WriteLine($"{VM.get_name_label(session, guest)} priority: '{wasPriority}' -> " +
            $"'{VM.get_ha_restart_priority(session, guest)}'");
        VM.set_ha_restart_priority(session, guest, wasPriority);

        // And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
        // failure HA should undo, or an administrator's intent it should respect?
        var restartOnInternalShutdown = Pool.get_ha_reboot_vm_on_internal_shutdown(session, poolRef);
        Console.WriteLine($"Restart on internal shutdown: {restartOnInternalShutdown}");
    }
    finally
    {
        // Turn HA back off however the above went: left on, it blocks host reboots, coordinator
        // changes and more (HA_IS_ENABLED, HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN).
        Pool.disable_ha(session);
    }
    Console.WriteLine($"HA enabled:    {Pool.get_ha_enabled(session, poolRef)}");
    Console.WriteLine("OK: configure-ha");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Heartbeat SR:  Shared NFS
Max failures:  1
HA enabled:    True
web-01 priority: '' -> 'restart'
Restart on internal shutdown: True
HA enabled:    False
OK: configure-ha
```

</details>

## Go

Source: [`go/configure_ha.go`](../../go/configure_ha.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// configureHa - Configure high availability.
//
// Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many
// host failures the pool can tolerate, enable HA, then disable it again.
//
// Run it:
//
//	configureHa("https://xenserver", "root", password, "Shared NFS")
func configureHa(url, user, password, heartbeatSRName string) {
	session := connect(url, user, password)
	pools, err := xenapi.Pool.GetAllRecords(session)
	check(err)
	var poolRef xenapi.PoolRef
	for ref := range pools {
		poolRef = ref
		break
	}

	// The HA heartbeat statefile needs a shared SR; confirm the chosen one can host it.
	srRef := srByName(session, heartbeatSRName, true)
	srName, _ := xenapi.SR.GetNameLabel(session, srRef)
	fmt.Printf("Heartbeat SR:  %s\n", srName)
	check(xenapi.SR.AssertCanHostHaStatefile(session, srRef))

	// What HA does per VM. The restart priority decides which guests come back first after a host
	// failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var guest xenapi.VMRef
	var guestName string
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && !v.IsASnapshot {
			guest, guestName = ref, v.NameLabel
			break
		}
	}

	// How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those: a target
	// computed with none protected can be too high, and protecting a VM afterwards then fails
	// HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN.
	ntol, err := xenapi.Pool.HaComputeHypotheticalMaxHostFailuresToTolerate(session,
		map[xenapi.VMRef]string{guest: "restart"})
	check(err)
	fmt.Printf("Max failures:  %d\n", ntol)
	check(xenapi.Pool.SetHaHostFailuresToTolerate(session, poolRef, ntol))
	check(xenapi.Pool.EnableHa(session, []xenapi.SRRef{srRef}, map[string]string{}))
	// Turn HA back off however the rest goes (check panics, and deferred calls still run): left on, it
	// blocks host reboots, coordinator changes and more (HA_IS_ENABLED, HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN).
	haOn := true
	defer func() {
		if haOn {
			_ = xenapi.Pool.DisableHa(session)
		}
	}()
	enabled, _ := xenapi.Pool.GetHaEnabled(session, poolRef)
	fmt.Printf("HA enabled:    %v\n", enabled)

	was, err := xenapi.VM.GetHaRestartPriority(session, guest)
	check(err)
	check(xenapi.VM.SetHaRestartPriority(session, guest, "restart"))
	now, _ := xenapi.VM.GetHaRestartPriority(session, guest)
	fmt.Printf("%s priority: %q -> %q\n", guestName, was, now)
	check(xenapi.VM.SetHaRestartPriority(session, guest, was))

	// And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a failure HA
	// should undo, or an administrator's intent it should respect?
	internal, _ := xenapi.Pool.GetHaRebootVMOnInternalShutdown(session, poolRef)
	fmt.Printf("Restart on internal shutdown: %v\n", internal)

	// Turn HA back off so the example is repeatable.
	check(xenapi.Pool.DisableHa(session))
	haOn = false
	enabled, _ = xenapi.Pool.GetHaEnabled(session, poolRef)
	fmt.Printf("HA enabled:    %v\n", enabled)
	fmt.Println("OK: configure-ha")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Heartbeat SR:  Shared NFS
Max failures:  1
HA enabled:    true
cache-01 priority: "" -> "restart"
Restart on internal shutdown: true
HA enabled:    false
OK: configure-ha
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureHa.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureHa.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureHa {
    private ConfigureHa() {
    }

    /**
     * Configure high availability.
     *
     * <p>Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many
     * host failures the pool can tolerate, enable HA, then disable it again.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureHa.run("https://xenserver", "root", password, "Shared NFS");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String heartbeatSrName) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAllRecords(conn).keySet().iterator().next();

        // The HA heartbeat statefile needs a shared SR; confirm the chosen one can host it.
        SR sr = srByName(conn, heartbeatSrName, true);
        System.out.println("Heartbeat SR:  " + sr.getNameLabel(conn));
        sr.assertCanHostHaStatefile(conn);

        // What HA does per VM. The restart priority decides which guests come back first after a host
        // failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
        VM guest = null;
        for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
            VM.Record r = e.getValue();
            if (!r.isATemplate && !r.isControlDomain && !r.isASnapshot) { guest = e.getKey(); break; }
        }

        // How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those:
        // a target computed with none protected can be too high, and protecting a VM afterwards then
        // fails HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN.
        Map<VM, String> plan = new java.util.HashMap<>();
        plan.put(guest, "restart");
        long ntol = Pool.haComputeHypotheticalMaxHostFailuresToTolerate(conn, plan);
        System.out.println("Max failures:  " + ntol);
        pool.setHaHostFailuresToTolerate(conn, ntol);
        Set<SR> heartbeatSrs = new LinkedHashSet<>();
        heartbeatSrs.add(sr);
        Pool.enableHa(conn, heartbeatSrs, new java.util.HashMap<>());
        try {
            System.out.println("HA enabled:    " + pool.getHaEnabled(conn));

            String was = guest.getHaRestartPriority(conn);
            guest.setHaRestartPriority(conn, "restart");
            System.out.println(guest.getNameLabel(conn) + " priority: '" + was + "' -> '"
                    + guest.getHaRestartPriority(conn) + "'");
            guest.setHaRestartPriority(conn, was);

            // And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
            // failure HA should undo, or an administrator's intent it should respect?
            boolean internal = pool.getHaRebootVmOnInternalShutdown(conn);
            System.out.println("Restart on internal shutdown: " + internal);
        } finally {
            // Turn HA back off however the above went: left on, it blocks host reboots, coordinator
            // changes and more (HA_IS_ENABLED, HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN).
            Pool.disableHa(conn);
        }
        System.out.println("HA enabled:    " + pool.getHaEnabled(conn));
        System.out.println("OK: configure-ha");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Heartbeat SR:  Shared NFS
Max failures:  1
HA enabled:    true
web-01 priority: '' -> 'restart'
Restart on internal shutdown: true
HA enabled:    false
OK: configure-ha
```

</details>
