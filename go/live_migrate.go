package main

import (
	"fmt"

	"go/xenapi"
)

// liveMigrate live-migrates a running VM to another host in the pool, with no downtime. Moves a
// throwaway copy of sourceVM, a VM with a guest OS and PV drivers: live migration needs the
// guest's cooperation (VM_LACKS_FEATURE without PV drivers). Only the VM's memory moves, so the
// destination host has to see its disks already: a disk on local storage refuses with
// VM_REQUIRES_SR. Put the copy's disks on the shared SR srName first.
//
// Run it:
//
//	liveMigrate("https://xenserver", "root", password, "web-01", "Shared NFS", "sdk-example-migrate")
func liveMigrate(url, user, password, sourceVM, srName, newVMName string) {
	session := connect(url, user, password)
	vm := copyOfGuest(session, sourceVM, newVMName)
	moveDisksToSR(session, vm, srByName(session, srName, true))
	check(xenapi.VM.Start(session, vm, false, true))
	waitForGuestAgent(session, vm)

	sourceHost, err := xenapi.VM.GetResidentOn(session, vm)
	check(err)
	srcName, _ := xenapi.Host.GetNameLabel(session, sourceHost)
	fmt.Printf("VM is running on: %s\n", srcName)

	// Pick a different host in the pool to receive the VM.
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var destHost xenapi.HostRef
	for ref := range hosts {
		if ref != sourceHost {
			destHost = ref
			break
		}
	}

	// Check the destination can boot it, then live-migrate (empty options = default live migration).
	check(xenapi.VM.AssertCanBootHere(session, vm, destHost))
	check(xenapi.VM.PoolMigrate(session, vm, destHost, map[string]string{}))

	nowHost, _ := xenapi.VM.GetResidentOn(session, vm)
	nowName, _ := xenapi.Host.GetNameLabel(session, nowHost)
	ps, _ := xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Migrated to:      %s\n", nowName)
	fmt.Printf("Still running:    %s\n", ps)

	// Tidy up so the example is repeatable.
	check(xenapi.VM.HardShutdown(session, vm))
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: live-migrate")
	session.Logout()
}
