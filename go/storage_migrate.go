package main

import (
	"fmt"

	"go/xenapi"
)

// storageMigrate relocates a running VM's disk to a different SR without stopping it (live
// storage migration) with VDI.PoolMigrate.
//
// Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
// so this works on a throwaway copy of sourceVM, a VM with a guest OS and PV drivers. (A halted
// VM's disk moves too, without the guest; what VDI.PoolMigrate always needs is a VM to move the
// disk for - a VDI no VBD points at fails VDI_NEEDS_VM_FOR_MIGRATE.)
//
// Run it:
//
//	storageMigrate("https://xenserver", "root", password, "web-01", "sdk-example-storagemigrate")
func storageMigrate(url, user, password, sourceVM, newVMName string) {
	session := connect(url, user, password)
	vm := copyOfGuest(session, sourceVM, newVMName)
	check(xenapi.VM.Start(session, vm, false, true))
	waitForGuestAgent(session, vm)
	vdi := diskVdis(session, vm)[0]
	sourceSr, err := xenapi.VDI.GetSR(session, vdi)
	check(err)
	srcSrName, _ := xenapi.SR.GetNameLabel(session, sourceSr)
	fmt.Printf("Disk is on SR: %s\n", srcSrName)

	// Pick a different SR that holds disks and that the VM's host can reach (an attached PBD there).
	host, err := xenapi.VM.GetResidentOn(session, vm)
	check(err)
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var destSr xenapi.SRRef
	found := false
	for ref, sr := range srs {
		if ref == sourceSr || sr.ContentType == "iso" || sr.Type == "iso" || sr.Type == "udev" {
			continue
		}
		for _, pbdRef := range sr.PBDs {
			pbdHost, err := xenapi.PBD.GetHost(session, pbdRef)
			check(err)
			attached, err := xenapi.PBD.GetCurrentlyAttached(session, pbdRef)
			check(err)
			if pbdHost == host && attached {
				destSr, found = ref, true
				break
			}
		}
		if found {
			break
		}
	}
	if !found {
		panic("no destination SR reachable from the VM's resident host was found")
	}

	// PoolMigrate returns the disk's new VDI: the copy on the destination SR replaces the original.
	vdi, err = xenapi.VDI.PoolMigrate(session, vdi, destSr, map[string]string{})
	check(err)

	nowOn, _ := xenapi.VDI.GetSR(session, vdi)
	nowName, _ := xenapi.SR.GetNameLabel(session, nowOn)
	fmt.Printf("Disk moved to:  %s\n", nowName)

	// Tidy up: the VM and the disks it now owns.
	check(xenapi.VM.HardShutdown(session, vm))
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: storage-migrate")
	session.Logout()
}
