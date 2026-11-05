package main

import (
	"fmt"

	"go/xenapi"
)

// cloneVM - Clone a VM.
//
// Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full
// copy — the quick way to stamp out new VMs from a halted "golden" image.
//
// Run it:
//
//	cloneVM("https://xenserver", "root", password, "db-01", "sdk-example-clone")
func cloneVM(url, user, password, vmName, cloneName string) {
	session := connect(url, user, password)
	// Unlike Copy (a full, independent copy onto a chosen SR), Clone is a fast copy-on-write
	// duplicate on the same SR - ideal for a halted "golden" VM.
	source := vmByName(session, vmName)

	// VM.Clone (like VM.Copy) requires a Halted source - VM_BAD_POWER_STATE otherwise - so shut a
	// running source down first and start it back up again afterwards, rather than assuming it is
	// already halted.
	wasRunning := false
	if state, _ := xenapi.VM.GetPowerState(session, source); state == xenapi.VMPowerStateRunning {
		wasRunning = true
		check(xenapi.VM.CleanShutdown(session, source))
	}

	clone, err := xenapi.VM.Clone(session, source, cloneName)
	check(err)
	srcName, _ := xenapi.VM.GetNameLabel(session, source)
	cloneLabel, _ := xenapi.VM.GetNameLabel(session, clone)
	fmt.Printf("Cloned '%s' -> %s\n", srcName, cloneLabel)
	vbds, _ := xenapi.VM.GetVBDs(session, clone)
	fmt.Printf("Clone has %d VBD(s)\n", len(vbds))

	if wasRunning {
		check(xenapi.VM.Start(session, source, false, true))
	}

	// Tidy up: destroy the clone and its (owned) disks.
	destroyVMAndDisks(session, clone)
	fmt.Println("OK: clone-vm")
	session.Logout()
}
