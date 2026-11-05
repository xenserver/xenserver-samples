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
