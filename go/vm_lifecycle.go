package main

import (
	"fmt"

	"go/xenapi"
)

// vmLifecycle takes a throwaway copy of a VM with a guest OS through start -> suspend -> resume ->
// clean shutdown, and deletes it again.
//
// Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
// so the copy is made from sourceVM, a VM with a guest OS and PV drivers, and the example waits
// for the guest to report in after starting. Suspend also needs a suspend-image SR (the VM's own,
// else the pool's, else the host's); check one is actually configured before trying.
func vmLifecycle(url, user, password, sourceVM, newVMName string) {
	session := connect(url, user, password)
	vmRef := copyOfGuest(session, sourceVM, newVMName)

	state := func() xenapi.VMPowerState {
		s, _ := xenapi.VM.GetPowerState(session, vmRef)
		return s
	}

	fmt.Printf("Initial power state: %s\n", state())
	check(xenapi.VM.Start(session, vmRef, false, true))
	waitForGuestAgent(session, vmRef)
	fmt.Printf("After start:    %s\n", state())

	// The emulated hardware (the device model) can be restarted under a running guest without
	// rebooting it - what you reach for when the VM's virtual devices misbehave.
	check(xenapi.VM.RestartDeviceModels(session, vmRef))
	fmt.Printf("Device models restarted; still %s\n", state())

	// Suspend needs a suspend-image SR (the VM's own, else the pool's, else the host's); check
	// one is actually configured before trying, rather than assuming it is (VM_NO_SUSPEND_SR
	// otherwise on a real host).
	if hasSuspendSR(session, vmRef) {
		check(xenapi.VM.Suspend(session, vmRef))
		fmt.Printf("After suspend:  %s\n", state())
		check(xenapi.VM.Resume(session, vmRef, false, true))
		waitForGuestAgent(session, vmRef) // the PV drivers reconnect after a resume
		fmt.Printf("After resume:   %s\n", state())
	} else {
		fmt.Println("Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host")
	}

	// A clean shutdown asks the guest OS to shut itself down, as pressing the power button would -
	// possible here because the copy has a guest OS with PV drivers.
	check(xenapi.VM.CleanShutdown(session, vmRef))
	fmt.Printf("After shutdown: %s\n", state())

	destroyVMAndDisks(session, vmRef)
	fmt.Println("OK: vm-lifecycle")
	session.Logout()
}

// hasSuspendSR reports whether VM.Suspend has a suspend-image SR to use: the VM's own, else the
// pool's, else the resident host's - the same fallback order xapi's choose_suspend_sr uses.
func hasSuspendSR(session *xenapi.Session, vm xenapi.VMRef) bool {
	if sr, err := xenapi.VM.GetSuspendSR(session, vm); err == nil && sr != "" && sr != "OpaqueRef:NULL" {
		return true
	}
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	if sr, err := xenapi.Pool.GetSuspendImageSR(session, pools[0]); err == nil && sr != "" && sr != "OpaqueRef:NULL" {
		return true
	}
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	sr, err := xenapi.Host.GetSuspendImageSr(session, host)
	return err == nil && sr != "" && sr != "OpaqueRef:NULL"
}
