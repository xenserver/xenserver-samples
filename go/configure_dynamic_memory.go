package main

import (
	"fmt"

	"go/xenapi"
)

// configureDynamicMemory - Configure dynamic memory.
//
// Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see
// the ordering rule the four bounds must obey enforced.
func configureDynamicMemory(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vm xenapi.VMRef
	var before xenapi.VMRecord
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && !v.IsASnapshot &&
			v.PowerState == xenapi.VMPowerStateHalted {
			vm, before = ref, v
			break
		}
	}
	fmt.Printf("%s: static %s-%s, dynamic %s-%s\n", before.NameLabel,
		gib(before.MemoryStaticMin), gib(before.MemoryStaticMax),
		gib(before.MemoryDynamicMin), gib(before.MemoryDynamicMax))

	// Room to balloon: let the host squeeze the VM down to a quarter of its maximum, but never below the
	// static floor, which is the least the guest can boot in.
	floor := before.MemoryStaticMax / 4
	if before.MemoryStaticMin > floor {
		floor = before.MemoryStaticMin
	}
	ceiling := before.MemoryStaticMax
	check(xenapi.VM.SetMemoryDynamicRange(session, vm, floor, ceiling))
	low, err := xenapi.VM.GetMemoryDynamicMin(session, vm)
	check(err)
	high, err := xenapi.VM.GetMemoryDynamicMax(session, vm)
	check(err)
	fmt.Printf("  dynamic range now %s-%s\n", gib(low), gib(high))

	// The ordering is enforced, not advisory: a range wider than the static bounds is refused rather than
	// quietly clamped.
	if err := xenapi.VM.SetMemoryDynamicRange(session, vm, floor, ceiling*2); err == nil {
		fmt.Println("  ERROR: an out-of-range maximum was accepted")
	} else {
		fmt.Printf("  refused a dynamic_max above static_max: %s\n", failureCode(err))
	}

	check(xenapi.VM.SetMemoryDynamicRange(session, vm, before.MemoryDynamicMin, before.MemoryDynamicMax))
	fmt.Println("OK: configure-dynamic-memory")
}

func gib(size int64) string {
	return fmt.Sprintf("%.1f GiB", float64(size)/(1024*1024*1024))
}
