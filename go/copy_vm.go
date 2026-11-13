package main

import (
	"fmt"

	"go/xenapi"
)

// copyVM - Copy a VM.
//
// Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks)
// — distinct from a fast, copy-on-write clone.
//
// Run it:
//
//	copyVM("https://xenserver", "root", password, "db-01", "Shared NFS", "sdk-example-copy")
func copyVM(url, user, password, vmName, srName, copyName string) {
	session := connect(url, user, password)
	// A full copy needs a halted source; it places an independent set of disks on the chosen SR.
	source := vmByName(session, vmName)
	srRef := srByName(session, srName, false)
	srLabel, _ := xenapi.SR.GetNameLabel(session, srRef)
	srcLabel, _ := xenapi.VM.GetNameLabel(session, source)
	fmt.Printf("Copying '%s' to SR: %s\n", srcLabel, srLabel)

	// VM.Copy (like VM.Clone) requires a Halted source - VM_BAD_POWER_STATE otherwise - so shut a
	// running source down first and start it back up again afterwards, rather than assuming it is
	// already halted.
	wasRunning := false
	if state, _ := xenapi.VM.GetPowerState(session, source); state == xenapi.VMPowerStateRunning {
		wasRunning = true
		check(xenapi.VM.CleanShutdown(session, source))
	}

	copyRef, err := xenapi.VM.Copy(session, source, copyName, srRef)
	check(err)
	uuid, _ := xenapi.VM.GetUUID(session, copyRef)
	vbds, _ := xenapi.VM.GetVBDs(session, copyRef)
	isTemplate, _ := xenapi.VM.GetIsATemplate(session, copyRef)
	fmt.Printf("Copied VM:     %s\n", uuid)
	fmt.Printf("Copy has %d VBD(s), is_a_template = %v\n", len(vbds), isTemplate)

	if wasRunning {
		check(xenapi.VM.Start(session, source, false, true))
	}

	// Tidy up: destroy the copy and its disks, leaving the source VM intact.
	destroyVMAndDisks(session, copyRef)
	fmt.Println("Cleaned up the copied VM (left the source intact).")
	fmt.Println("OK: copy-vm")
	session.Logout()
}
