<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Restart a host

Take a host down and bring it back: stop it accepting new VMs, move the ones it is running elsewhere, reboot it, then power it right off and back on again.

**Caution:** reboots a host.

Workflow `restart-host`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-RestartHost.ps1`](../../powershell/HostsAndPools/Invoke-RestartHost.ps1)

```powershell
function Invoke-RestartHost {
    <#
    .SYNOPSIS
        Restart a host.
    .DESCRIPTION
        Take a host down and bring it back: stop it accepting new VMs, move the ones it is running
        elsewhere, reboot it, then power it right off and back on again.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # Rebooting a host is never just the reboot: anything running on it has to go somewhere first, and the
    # host has to stop accepting new VMs while that happens.
    #
    # Not the coordinator: it is the host this session is talking to, and taking it down would drop the
    # connection underneath the rest of the example.
    $pool = Get-XenPool | Select-Object -First 1
    $xenHost = Get-XenHost | Where-Object { $pool.master -ne $_ } | Select-Object -First 1
    Write-Host "Restarting $($xenHost.name_label)"
    Write-Host "  enabled=$($xenHost.enabled), guests=$(Measure-HostGuest $xenHost)"

    # Disabled means "accept no new VMs"; it does not move anything on its own.
    $xenHost | Invoke-XenHost -XenAction Disable
    Write-Host "  disabled:   enabled=$((Get-XenHost -Ref $xenHost).enabled)"

    # Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain - the host's own
    # management VM, which cannot move - is left.
    Invoke-Evacuate -XenHost $xenHost
    Write-Host "  evacuated:  guests=$(Measure-HostGuest $xenHost)"

    $xenHost | Invoke-XenHost -XenAction Reboot
    # A real reboot takes minutes. Wait for the host to drop out and come back (live in its
    # host_metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
    # itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
    # never does - so enable it explicitly rather than depend on either.
    Wait-HostLive -XenHost $xenHost -Want $false -TimeoutSeconds 600
    Wait-HostLive -XenHost $xenHost -Want $true -TimeoutSeconds 1200 -IntervalSeconds 10
    Enable-WhenBooted -XenHost $xenHost
    Write-Host "  rebooted, re-enabled: enabled=$((Get-XenHost -Ref $xenHost).enabled)"

    # The other ending: off, and back on out of band - but only demonstrated if that is actually
    # configured, and waiting for each transition before starting the next: host.power_on has no retry
    # of its own and simply fails, "The host failed to power on.", if no mechanism is configured or
    # working.
    if ((Get-XenHost -Ref $xenHost).power_on_mode) {
        $xenHost | Invoke-XenHost -XenAction Disable
        $xenHost | Invoke-XenHost -XenAction Shutdown
        Wait-HostLive -XenHost $xenHost -Want $false
        Write-Host "  shut down:  live=$(Get-HostLive $xenHost)"
        $xenHost | Invoke-XenHost -XenAction PowerOn
        Wait-HostLive -XenHost $xenHost -Want $true -TimeoutSeconds 1200 -IntervalSeconds 10
        Write-Host "  powered on: live=$(Get-HostLive $xenHost)"
        Enable-WhenBooted -XenHost $xenHost
        Write-Host "  re-enabled: enabled=$((Get-XenHost -Ref $xenHost).enabled)"
    }
    else {
        Write-Host "  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host"
    }

    Write-Host "OK: restart-host"
    $session | Disconnect-XenServer
}

function Measure-HostGuest {
    <#
    .SYNOPSIS
        Resident VMs excluding the control domain, which never moves.
    #>
    param($XenHost)
    @((Get-XenHost -Ref $XenHost).resident_VMs |
        Where-Object { -not (Get-XenVM -Ref $_).is_control_domain }).Count
}

function Wait-HostLive {
    <#
    .SYNOPSIS
        Poll host_metrics.live until it matches, rather than issuing the next power command immediately -
        real out-of-band power control has no retry of its own, so a tool that doesn't wait can issue a
        second command while the first is still in flight.
    #>
    param($XenHost, [bool]$Want, [int]$TimeoutSeconds = 60, [int]$IntervalSeconds = 2)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-HostLive $XenHost) -ne $Want) {
        if ((Get-Date) -gt $deadline) { throw "host did not reach live=$Want in time" }
        Start-Sleep -Seconds $IntervalSeconds
    }
}
```

<details><summary>Example output</summary>

```text
Restarting sdk-host2
  enabled=True, guests=0
  disabled:   enabled=False
  evacuated:  guests=0
  rebooted, re-enabled: enabled=True
  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host
OK: restart-host
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/restart-host.sh`](../../cli/hosts-and-pools/restart-host.sh)

```bash
# Restart a host.
#
# Take a host down and bring it back: stop it accepting new VMs, move the ones it is running elsewhere, reboot
# it, then power it right off and back on again.
#
# Run it:
#   ./workflows.sh restart-host https://xenserver root "$password"

restart_host() {
    # Rebooting a host is never just the reboot: anything running on it has to go somewhere first, and the
    # host has to stop accepting new VMs while that happens.
    #
    # Not the coordinator: it is the host xe is talking to, and taking it down would drop the connection
    # underneath the rest of the example.
    pool=$(first_csv "$(xe pool-list --minimal)")
    coordinator=$(xe pool-param-get uuid=$pool param-name=master)
    target=""
    for h in $(each_csv "$(xe host-list --minimal)"); do
        if [ "$h" != "$coordinator" ]; then target=$h; break; fi
    done
    echo "Restarting $(xe host-param-get uuid=$target param-name=name-label)"
    echo "  enabled=$(xe host-param-get uuid=$target param-name=enabled), guests=$(count_host_guest $target)"

    # Disabled means "accept no new VMs"; it does not move anything on its own.
    xe host-disable uuid=$target
    echo "  disabled:   enabled=$(xe host-param-get uuid=$target param-name=enabled)"

    # Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain - the host's own
    # management VM, which cannot move - is left.
    xe host-evacuate uuid=$target
    echo "  evacuated:  guests=$(count_host_guest $target)"

    xe host-reboot uuid=$target
    # A real reboot takes minutes. Wait for the host to drop out and come back (live in its
    # host-metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
    # itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
    # never does - so enable it explicitly rather than depend on either.
    wait_for_host_live "$target" false 600
    wait_for_host_live "$target" true 1200 10
    enable_when_booted "$target"
    echo "  rebooted, re-enabled: enabled=$(xe host-param-get uuid=$target param-name=enabled)"

    # The other ending: off, and back on out of band - but only demonstrated if that is actually
    # configured (host-power-on has no fallback and simply fails if no mechanism is configured or
    # working), and waiting for each transition before starting the next.
    if [ -n "$(xe host-param-get uuid=$target param-name=power-on-mode)" ]; then
        xe host-disable uuid=$target
        xe host-shutdown uuid=$target
        wait_for_host_live "$target" false
        echo "  shut down:  live=$(host_live $target)"
        xe host-power-on uuid=$target
        wait_for_host_live "$target" true 1200 10
        echo "  powered on: live=$(host_live $target)"
        enable_when_booted "$target"
        echo "  re-enabled: enabled=$(xe host-param-get uuid=$target param-name=enabled)"
    else
        echo "  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host"
    fi
    echo "OK: restart-host"
}

# Poll host_metrics.live until it matches, rather than issuing the next power command immediately - real
# out-of-band power control has no retry of its own, so a script that doesn't wait can issue a second
# command while the first is still in flight.
wait_for_host_live() {
    local h=$1 want=$2 timeout=${3:-60} interval=${4:-2}
    local deadline=$((SECONDS + timeout))
    while [ "$(host_live "$h")" != "$want" ]; do
        if [ $SECONDS -gt $deadline ]; then
            echo "host did not reach live=$want in time" >&2
            return 1
        fi
        sleep "$interval"
    done
}

# Resident VMs excluding the control domain, which never moves.
count_host_guest() {
    local n=0
    for vm in $(each_csv "$(set_to_csv "$(xe host-param-get uuid=$1 param-name=resident-VMs)")"); do
        if [ "$(xe vm-param-get uuid=$vm param-name=is-control-domain)" != "true" ]; then n=$((n + 1)); fi
    done
    echo $n
}
```

<details><summary>Example output</summary>

```text
Restarting sdk-host2
  enabled=true, guests=0
  disabled:   enabled=false
  evacuated:  guests=0
  rebooted, re-enabled: enabled=true
  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host
OK: restart-host
```

</details>

## Python

Source: [`python/hosts_and_pools/restart_host.py`](../../python/hosts_and_pools/restart_host.py)

```python
"""Restart a host.

Take a host down and bring it back: stop it accepting new VMs, move the ones it is running
elsewhere, reboot it, then power it right off and back on again.
"""

import time

from connection import connect
from helpers import enable_when_booted, host_live


def restart_host(url, username, password):
    """Take a host down and bring it back.

    Rebooting a host is never just the reboot: anything running on it has to go
    somewhere first, and the host has to stop accepting new VMs while that happens.
    Disable, evacuate, reboot, re-enable. Disabling with the default auto_enable=true clears itself
    once the host's toolstack is back up; an explicit enable doesn't depend on that, or on when.
    Powering it right off and back on again is a second, separate demonstration, and only a
    meaningful one if the host actually has an out-of-band power-on mode configured: a real
    host.power_on has no retry of its own and simply fails if none is set up, leaving the host off
    with no API-level way to revive it."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    # Not the coordinator: it is the host this session is talking to, and taking it down
    # would drop the connection underneath the rest of the example.
    coordinator = x.pool.get_master(pool)
    host = next(h for h in x.host.get_all() if h != coordinator)
    print("Restarting %s" % x.host.get_name_label(host))
    print("  enabled=%s, guests=%d" % (x.host.get_enabled(host), guest_count(x, host)))

    # Disabled means "accept no new VMs"; it does not move anything on its own.
    x.host.disable(host)
    print("  disabled:   enabled=%s" % x.host.get_enabled(host))

    # Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain
    # -- the host's own management VM, which cannot move -- is left.
    x.host.evacuate(host)
    print("  evacuated:  guests=%d" % guest_count(x, host))

    x.host.reboot(host)
    # A real reboot takes minutes. Wait for the host to drop out and come back (live in its
    # host_metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
    # itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
    # never does - so enable it explicitly rather than depend on either.
    _wait_for_host_live(x, host, False, timeout=600)
    _wait_for_host_live(x, host, True, timeout=1200, interval=10)
    enable_when_booted(x, host)
    print("  rebooted, re-enabled: enabled=%s" % x.host.get_enabled(host))

    # The other ending: off, and back on out of band -- but only demonstrated if that is actually
    # configured, and waiting for each transition before starting the next.
    if x.host.get_power_on_mode(host):
        x.host.disable(host)
        x.host.shutdown(host)
        _wait_for_host_live(x, host, False)
        print("  shut down:  live=%s" % host_live(x, host))
        x.host.power_on(host)
        _wait_for_host_live(x, host, True, timeout=1200, interval=10)
        print("  powered on: live=%s" % host_live(x, host))
        enable_when_booted(x, host)
        print("  re-enabled: enabled=%s" % x.host.get_enabled(host))
    else:
        print("  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host")

    print("OK: restart-host")
    session.logout()


def _wait_for_host_live(x, host, want, timeout=60, interval=2):
    """Poll host_metrics.live until it matches, rather than issuing the next power command
    immediately - real out-of-band power control has no retry of its own, so a tool that doesn't
    wait can issue a second command while the first is still in flight."""
    deadline = time.time() + timeout
    while host_live(x, host) != want:
        if time.time() > deadline:
            raise RuntimeError("host did not reach live=%s in time" % want)
        time.sleep(interval)


def guest_count(x, host):
    """Resident VMs excluding the control domain, which never moves."""
    return len([v for v in x.host.get_resident_VMs(host)
                if not x.VM.get_is_control_domain(v)])
```

<details><summary>Example output</summary>

```text
Restarting sdk-host2
  enabled=True, guests=0
  disabled:   enabled=False
  evacuated:  guests=0
  rebooted, re-enabled: enabled=True
  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host
OK: restart-host
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/RestartHost.cs`](../../csharp/HostsAndPools/RestartHost.cs)

```csharp
/// <summary>
/// Take a host down and bring it back: stop it accepting new VMs, move the ones it is running elsewhere,
/// reboot it, then power it right off and back on again.
/// </summary>
public static void RestartHost(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session).First();

    // Rebooting a host is never just the reboot: anything running on it has to go somewhere first,
    // and the host has to stop accepting new VMs while that happens.
    //
    // Not the coordinator: it is the host this session is talking to, and taking it down would drop
    // the connection underneath the rest of the example.
    var coordinator = Pool.get_master(session, pool);
    var host = Host.get_all(session).First(h => !h.Equals(coordinator));
    Console.WriteLine($"Restarting {Host.get_name_label(session, host)}");
    Console.WriteLine($"  enabled={Host.get_enabled(session, host)}, guests={GuestCount(session, host)}");

    // Disabled means "accept no new VMs"; it does not move anything on its own.
    Host.disable(session, host);
    Console.WriteLine($"  disabled:   enabled={Host.get_enabled(session, host)}");

    // Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain — the
    // host's own management VM, which cannot move — is left.
    Host.evacuate(session, host);
    Console.WriteLine($"  evacuated:  guests={GuestCount(session, host)}");

    Host.reboot(session, host);
    // A real reboot takes minutes. Wait for the host to drop out and come back (live in its
    // host_metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
    // itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
    // never does - so enable it explicitly rather than depend on either.
    WaitForHostLive(session, host, false, 600);
    WaitForHostLive(session, host, true, 1200, 10);
    EnableWhenBooted(session, host);
    Console.WriteLine($"  rebooted, re-enabled: enabled={Host.get_enabled(session, host)}");

    // The other ending: off, and back on out of band - but only demonstrated if that is actually
    // configured: a real host.power_on has no retry of its own and simply fails,
    // "The host failed to power on.", if no mechanism is configured or working.
    if (!string.IsNullOrEmpty(Host.get_power_on_mode(session, host)))
    {
        Host.disable(session, host);
        Host.shutdown(session, host);
        WaitForHostLive(session, host, false);
        Console.WriteLine($"  shut down:  live={HostLive(session, host)}");
        Host.power_on(session, host);
        WaitForHostLive(session, host, true, 1200, 10);
        Console.WriteLine($"  powered on: live={HostLive(session, host)}");
        EnableWhenBooted(session, host);
        Console.WriteLine($"  re-enabled: enabled={Host.get_enabled(session, host)}");
    }
    else
    {
        Console.WriteLine("  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host");
    }

    Console.WriteLine("OK: restart-host");
    session.logout();
}

/// <summary>
/// Poll host_metrics.live until it matches, rather than issuing the next power command immediately -
/// real out-of-band power control has no retry of its own, so a tool that doesn't wait can issue a
/// second command while the first is still in flight.
/// </summary>
private static void WaitForHostLive(Session session, XenRef<Host> host, bool want,
    int timeoutSeconds = 60, int intervalSeconds = 2)
{
    var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
    while (HostLive(session, host) != want)
    {
        if (DateTime.UtcNow > deadline) throw new Exception($"host did not reach live={want} in time");
        System.Threading.Thread.Sleep(intervalSeconds * 1000);
    }
}

/// <summary>Resident VMs excluding the control domain, which never moves.</summary>
private static int GuestCount(Session session, XenRef<Host> host) =>
    Host.get_resident_VMs(session, host).Count(v => !VM.get_is_control_domain(session, v));
```

<details><summary>Example output</summary>

```text
Restarting sdk-host2
  enabled=True, guests=0
  disabled:   enabled=False
  evacuated:  guests=0
  rebooted, re-enabled: enabled=True
  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host
OK: restart-host
```

</details>

## Go

Source: [`go/restart_host.go`](../../go/restart_host.go)

```go
package main

import (
	"fmt"
	"time"

	"go/xenapi"
)

// restartHost - Restart a host.
//
// Take a host down and bring it back: stop it accepting new VMs, move the ones it is running
// elsewhere, reboot it, then power it right off and back on again.
func restartHost(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	// Rebooting a host is never just the reboot: anything running on it has to go somewhere first, and
	// the host has to stop accepting new VMs while that happens.
	//
	// Not the coordinator: it is the host this session is talking to, and taking it down would drop the
	// connection underneath the rest of the example.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	coordinator, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	var host xenapi.HostRef
	for _, h := range hosts {
		if h != coordinator {
			host = h
			break
		}
	}
	name, _ := xenapi.Host.GetNameLabel(session, host)
	enabled, _ := xenapi.Host.GetEnabled(session, host)
	fmt.Printf("Restarting %s\n", name)
	fmt.Printf("  enabled=%t, guests=%d\n", enabled, guestCount(session, host))

	// Disabled means "accept no new VMs"; it does not move anything on its own.
	check(xenapi.Host.Disable(session, host, true))
	enabled, _ = xenapi.Host.GetEnabled(session, host)
	fmt.Printf("  disabled:   enabled=%t\n", enabled)

	// Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain - the host's
	// own management VM, which cannot move - is left.
	check(xenapi.Host.Evacuate2(session, host))
	fmt.Printf("  evacuated:  guests=%d\n", guestCount(session, host))

	check(xenapi.Host.Reboot(session, host))
	// A real reboot takes minutes. Wait for the host to drop out and come back (live in its
	// host_metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
	// itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
	// never does - so enable it explicitly rather than depend on either.
	waitForHostLiveTimeout(session, host, false, 600*time.Second, 2*time.Second)
	waitForHostLiveTimeout(session, host, true, 1200*time.Second, 10*time.Second)
	enableWhenBooted(session, host)
	enabled, _ = xenapi.Host.GetEnabled(session, host)
	fmt.Printf("  rebooted, re-enabled: enabled=%t\n", enabled)

	// The other ending: off, and back on out of band - but only demonstrated if that is actually
	// configured (host.power_on has no fallback and simply fails if no mechanism is configured or
	// working), and waiting for each transition before starting the next.
	mode, _ := xenapi.Host.GetPowerOnMode(session, host)
	if mode != "" {
		check(xenapi.Host.Disable(session, host, true))
		check(xenapi.Host.Shutdown(session, host))
		waitForHostLive(session, host, false)
		fmt.Printf("  shut down:  live=%t\n", hostLive(session, host))
		check(xenapi.Host.PowerOn(session, host))
		waitForHostLiveTimeout(session, host, true, 1200*time.Second, 10*time.Second)
		fmt.Printf("  powered on: live=%t\n", hostLive(session, host))
		enableWhenBooted(session, host)
		enabled, _ = xenapi.Host.GetEnabled(session, host)
		fmt.Printf("  re-enabled: enabled=%t\n", enabled)
	} else {
		fmt.Println("  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host")
	}

	fmt.Println("OK: restart-host")
}

// waitForHostLive polls host_metrics.live until it matches, rather than issuing the next power
// command immediately - real out-of-band power control has no retry of its own, so a tool that
// doesn't wait can issue a second command while the first is still in flight.
func waitForHostLive(session *xenapi.Session, host xenapi.HostRef, want bool) {
	waitForHostLiveTimeout(session, host, want, 60*time.Second, 2*time.Second)
}

func waitForHostLiveTimeout(session *xenapi.Session, host xenapi.HostRef, want bool, timeout, interval time.Duration) {
	deadline := time.Now().Add(timeout)
	for hostLive(session, host) != want {
		if time.Now().After(deadline) {
			panic(fmt.Sprintf("host did not reach live=%t in time", want))
		}
		time.Sleep(interval)
	}
}

// guestCount reports resident VMs excluding the control domain, which never moves.
func guestCount(session *xenapi.Session, host xenapi.HostRef) int {
	resident, err := xenapi.Host.GetResidentVMs(session, host)
	check(err)
	n := 0
	for _, vm := range resident {
		if dom0, _ := xenapi.VM.GetIsControlDomain(session, vm); !dom0 {
			n++
		}
	}
	return n
}
```

<details><summary>Example output</summary>

```text
Restarting sdk-host2
  enabled=true, guests=0
  disabled:   enabled=false
  evacuated:  guests=0
  rebooted, re-enabled: enabled=true
  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host
OK: restart-host
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/RestartHost.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/RestartHost.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.enableWhenBooted;
import static com.xenserver.samples.PoolConnection.connect;

public final class RestartHost {
    private RestartHost() {
    }

    /**
     * Restart a host.
     *
     * <p>Take a host down and bring it back: stop it accepting new VMs, move the ones it is running
     * elsewhere, reboot it, then power it right off and back on again.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Rebooting a host is never just the reboot: anything running on it has to go somewhere
            // first, and the host has to stop accepting new VMs while that happens.
            //
            // Not the coordinator: it is the host this session is talking to, and taking it down would
            // drop the connection underneath the rest of the example.
            Host coordinator = Pool.getAll(conn).iterator().next().getMaster(conn);
            Host host = null;
            for (Host h : Host.getAll(conn)) if (!h.equals(coordinator)) { host = h; break; }

            System.out.println("Restarting " + host.getNameLabel(conn));
            System.out.printf("  enabled=%s, guests=%d%n", host.getEnabled(conn), guestCount(conn, host));

            // Disabled means "accept no new VMs"; it does not move anything on its own.
            host.disable(conn);
            System.out.println("  disabled:   enabled=" + host.getEnabled(conn));

            // Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain - the
            // host's own management VM, which cannot move - is left.
            host.evacuate(conn);
            System.out.printf("  evacuated:  guests=%d%n", guestCount(conn, host));

            host.reboot(conn);
            // A real reboot takes minutes. Wait for the host to drop out and come back (live in its
            // host_metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
            // itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
            // never does - so enable it explicitly rather than depend on either.
            waitForHostLive(conn, host, false, 600_000, 2_000);
            waitForHostLive(conn, host, true, 1_200_000, 10_000);
            enableWhenBooted(conn, host);
            System.out.println("  rebooted, re-enabled: enabled=" + host.getEnabled(conn));

            // The other ending: off, and back on out of band - but only demonstrated if that is actually
            // configured, and waiting for each transition before starting the next. A real host.power_on
            // has no retry of its own and simply fails, "The host failed to power on.", if no mechanism is
            // configured or working.
            if (host.getPowerOnMode(conn) != null && !host.getPowerOnMode(conn).isEmpty()) {
                host.disable(conn);
                host.shutdown(conn);
                waitForHostLive(conn, host, false);
                System.out.println("  shut down:  live=" + host.getMetrics(conn).getLive(conn));
                host.powerOn(conn);
                waitForHostLive(conn, host, true, 1_200_000, 10_000);
                System.out.println("  powered on: live=" + host.getMetrics(conn).getLive(conn));
                enableWhenBooted(conn, host);
                System.out.println("  re-enabled: enabled=" + host.getEnabled(conn));
            } else {
                System.out.println("  skipping shutdown/power-on: no out-of-band power-on mode is "
                        + "configured on this host");
            }

            System.out.println("OK: restart-host");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Poll host_metrics.live until it matches, rather than issuing the next power command immediately -
     * real out-of-band power control has no retry of its own, so a tool that doesn't wait can issue a
     * second command while the first is still in flight.
     */
    private static void waitForHostLive(Connection conn, Host host, boolean want) throws Exception {
        waitForHostLive(conn, host, want, 60_000, 2000);
    }

    private static void waitForHostLive(Connection conn, Host host, boolean want, long timeoutMillis,
            long intervalMillis) throws Exception {
        long deadline = System.currentTimeMillis() + timeoutMillis;
        while (host.getMetrics(conn).getLive(conn) != want) {
            if (System.currentTimeMillis() > deadline)
                throw new RuntimeException("host did not reach live=" + want + " in time");
            Thread.sleep(intervalMillis);
        }
    }

    /**
     * Resident VMs excluding the control domain, which never moves.
     */
    private static int guestCount(Connection conn, Host host) throws Exception {
        int n = 0;
        for (VM vm : host.getResidentVMs(conn)) if (!vm.getIsControlDomain(conn)) n++;
        return n;
    }
}
```

<details><summary>Example output</summary>

```text
Restarting sdk-host2
  enabled=true, guests=0
  disabled:   enabled=false
  evacuated:  guests=0
  rebooted, re-enabled: enabled=true
  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host
OK: restart-host
```

</details>
