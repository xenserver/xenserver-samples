package main

import (
	"fmt"

	"go/xenapi"
)

// hostMaintenance disables a host, evacuates its running guests to another host, then re-enables
// it. Pins a throwaway copy of sourceVM to the host so evacuation has work to do. Evacuation
// live-migrates the guest, which needs its cooperation (VM_LACKS_FEATURE without PV drivers), so
// sourceVM must have a guest OS with PV drivers.
//
// Run it:
//
//	hostMaintenance("https://xenserver", "root", password, "web-01", "Shared NFS", "sdk-example-maint")
func hostMaintenance(url, user, password, sourceVM, srName, newVMName string) {
	session := connect(url, user, password)
	// Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
	pools, err := xenapi.Pool.GetAllRecords(session)
	check(err)
	var master xenapi.HostRef
	for _, p := range pools {
		master = p.Master
		break
	}
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var hostRef xenapi.HostRef
	for ref := range hosts {
		if ref != master {
			hostRef = ref
			break
		}
	}
	hostName, _ := xenapi.Host.GetNameLabel(session, hostRef)
	fmt.Printf("Maintenance host: %s\n", hostName)

	// Pin a running VM to that host so evacuation has something to move.
	vm := copyOfGuest(session, sourceVM, newVMName)
	// Evacuation needs somewhere else in the pool that can actually see the VM's disk - a VM whose
	// only disk is on local (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a
	// pool's installation-time default SR is commonly local storage. Put the pinned VM's disk on a
	// shared SR explicitly rather than trusting whatever the pool default happens to be.
	moveDisksToSR(session, vm, srByName(session, srName, true))
	check(xenapi.VM.SetAffinity(session, vm, hostRef))
	check(xenapi.VM.Start(session, vm, false, true))
	waitForGuestAgent(session, vm)
	on, _ := xenapi.VM.GetResidentOn(session, vm)
	onName, _ := xenapi.Host.GetNameLabel(session, on)
	fmt.Printf("Guest resident on:%s\n", onName)

	// Enter maintenance mode: disable the host, then evacuate its guests.
	check(xenapi.Host.Disable(session, hostRef, true))
	enabled, _ := xenapi.Host.GetEnabled(session, hostRef)
	fmt.Printf("After disable:    host.enabled = %v\n", enabled)
	check(xenapi.Host.Evacuate2(session, hostRef))
	moved, _ := xenapi.VM.GetResidentOn(session, vm)
	movedName, _ := xenapi.Host.GetNameLabel(session, moved)
	fmt.Printf("After evacuate:   guest now on %s\n", movedName)

	// Exit maintenance mode.
	check(xenapi.Host.Enable(session, hostRef))
	enabled, _ = xenapi.Host.GetEnabled(session, hostRef)
	fmt.Printf("After enable:     host.enabled = %v\n", enabled)

	// Tidy up so the example is repeatable.
	check(xenapi.VM.HardShutdown(session, vm))
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: host-maintenance")
	session.Logout()
}
