package main

import (
	"fmt"

	"go/xenapi"
)

// snapshotSchedule - Snapshot schedule.
//
// Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention
// limit prune the oldest snapshot away.
func snapshotSchedule(url, user, password, vmName, scheduleName string) {
	session := connect(url, user, password)
	vmRef := vmByName(session, vmName)

	// RetainedSnapshots is the interesting field: the schedule prunes to it every time it runs.
	vmssRef, err := xenapi.VMSS.Create(session, xenapi.VMSSRecord{
		NameLabel:         scheduleName,
		NameDescription:   "Scheduled snapshots created by the SDK example",
		Enabled:           true,
		Type:              xenapi.VmssTypeSnapshot,
		Frequency:         xenapi.VmssFrequencyDaily,
		RetainedSnapshots: 2,
		Schedule:          map[string]string{"hour": "2", "min": "0"},
	})
	check(err)
	vmssUUID, _ := xenapi.VMSS.GetUUID(session, vmssRef)
	fmt.Printf("Created schedule: %s\n", vmssUUID)

	check(xenapi.VM.SetSnapshotSchedule(session, vmRef, vmssRef))
	members, _ := xenapi.VMSS.GetVMs(session, vmssRef)
	fmt.Printf("Members:          %d\n", len(members))

	// Run it three times against a retention of two: the oldest is pruned away. Compare against the
	// snapshots the VM already had, so only the schedule's own are counted (and tidied up below).
	existing, err := xenapi.VM.GetSnapshots(session, vmRef)
	check(err)
	before := map[xenapi.VMRef]bool{}
	for _, s := range existing {
		before[s] = true
	}
	for i := 0; i < 3; i++ {
		_, err = xenapi.VMSS.SnapshotNow(session, vmssRef)
		check(err)
	}
	snaps, err := xenapi.VM.GetSnapshots(session, vmRef)
	check(err)
	var kept []xenapi.VMRef
	for _, s := range snaps {
		if !before[s] {
			kept = append(kept, s)
		}
	}
	fmt.Printf("Snapshots kept:   %d (retention 2)\n", len(kept))

	// Tidy up: a schedule with VMs still on it cannot be destroyed (VMSS_HAS_VM), so take the VM off it
	// first. Destroying the schedule leaves the snapshots it took, so destroy those too, with their disks.
	check(xenapi.VM.SetSnapshotSchedule(session, vmRef, "OpaqueRef:NULL"))
	check(xenapi.VMSS.Destroy(session, vmssRef))
	for _, s := range kept {
		destroyVMAndDisks(session, s)
	}
	fmt.Println("OK: snapshot-schedule")
	session.Logout()
}
