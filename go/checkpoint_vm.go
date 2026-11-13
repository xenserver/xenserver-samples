package main

import (
	"fmt"

	"go/xenapi"
)

// checkpointVM checkpoints a throwaway copy of a VM with a guest OS, then reverts it back to that
// checkpoint. A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be
// running. Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
// hence a copy of sourceVM - a VM with a guest OS and PV drivers - rather than an OS-less template
// clone.
//
// Run it:
//
//	checkpointVM("https://xenserver", "root", password, "web-01", "sdk-example-checkpoint")
func checkpointVM(url, user, password, sourceVM, newVMName string) {
	session := connect(url, user, password)
	vm := copyOfGuest(session, sourceVM, newVMName)
	check(xenapi.VM.Start(session, vm, false, true))
	waitForGuestAgent(session, vm)

	checkpoint, err := xenapi.VM.Checkpoint(session, vm, "sdk-example-checkpoint-1")
	check(err)
	uuid, _ := xenapi.VM.GetUUID(session, checkpoint)
	fmt.Printf("Created checkpoint: %s\n", uuid)
	isSnapshot, _ := xenapi.VM.GetIsASnapshot(session, checkpoint)
	fmt.Printf("is_a_snapshot = %v\n", isSnapshot)

	check(xenapi.VM.Revert(session, checkpoint))
	// A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
	// VM.Revert restores exactly that - so the VM is Suspended here, not Running as it was before
	// the checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.Resume clears
	// that: destroying a Suspended VM directly (as a bare "if Running: hard_shutdown" guard would,
	// since the VM is never Running here) leaves that suspend_VDI behind as a storage leak.
	ps, _ := xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Reverted the VM to the checkpoint; power state now: %s\n", ps)
	check(xenapi.VM.Resume(session, vm, false, true))

	// Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
	destroyVMAndDisks(session, checkpoint)
	check(xenapi.VM.HardShutdown(session, vm))
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: checkpoint-vm")
	session.Logout()
}
