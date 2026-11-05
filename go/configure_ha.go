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
