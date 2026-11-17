package main

import (
	"fmt"

	"go/xenapi"
)

// checkpointVM checkpoints a running VM with a guest OS, reverts it to that checkpoint and resumes
// it. A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
// Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest
// freezes its processes and suspends itself. A guest that is still booting can fail to freeze a
// process that is busy starting up, and it then abandons the suspend without telling the host, which
// waits until VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here.
//
// Run it:
//
//	checkpointVM("https://xenserver", "root", password, "web-01")
func checkpointVM(url, user, password, vmName string) {
	session := connect(url, user, password)
	defer session.Logout()
	vm := vmByName(session, vmName)
	state, err := xenapi.VM.GetPowerState(session, vm)
	check(err)
	if state != xenapi.VMPowerStateRunning {
		panic(fmt.Sprintf("%s must be running to be checkpointed", vmName))
	}

	checkpoint, err := xenapi.VM.Checkpoint(session, vm, "sdk-example-checkpoint-1")
	check(err)
	uuid, _ := xenapi.VM.GetUUID(session, checkpoint)
	fmt.Printf("Created checkpoint: %s\n", uuid)
	isSnapshot, _ := xenapi.VM.GetIsASnapshot(session, checkpoint)
	fmt.Printf("is_a_snapshot = %v\n", isSnapshot)

	check(xenapi.VM.Revert(session, checkpoint))
	// A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
	// VM.Revert restores exactly that - so the VM is Suspended here, not Running as it was before
	// the checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.Resume picks up
	// from there (and frees that memory image).
	ps, _ := xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Reverted %s to the checkpoint; power state now: %s\n", vmName, ps)
	check(xenapi.VM.Resume(session, vm, false, true))
	ps, _ = xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Resumed %s; power state now: %s\n", vmName, ps)

	// Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
	destroyVMAndDisks(session, checkpoint)
	fmt.Println("Deleted the checkpoint.")
	fmt.Println("OK: checkpoint-vm")
}
