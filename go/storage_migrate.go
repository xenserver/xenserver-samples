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
	defer session.Logout()
	vm := copyOfGuest(session, sourceVM, newVMName)
	check(xenapi.VM.Start(session, vm, false, true))
	waitForGuestAgent(session, vm)
	vdi := diskVdis(session, vm)[0]
	sourceSR, err := xenapi.VDI.GetSR(session, vdi)
	check(err)
	srcSRName, _ := xenapi.SR.GetNameLabel(session, sourceSR)
	fmt.Printf("Disk is on SR: %s\n", srcSRName)

	// Pick a different SR that holds disks, that the VM's host can reach (an attached PBD there), and
	// that has room for the disk - a host's local SR is often too small for a VM's disk. Scan a candidate
	// before trusting its free space: the size and utilisation xapi reports are only as fresh as the SR's
	// last scan, and can claim room the storage doesn't have. Live storage migration copies a snapshot of
	// the disk and mirrors the running disk on top of it, so the destination needs room for the disk twice
	// over (a thick-provisioned LVM SR allocates both).
	const GiB = 1024 * 1024 * 1024
	host, err := xenapi.VM.GetResidentOn(session, vm)
	check(err)
	size, err := xenapi.VDI.GetVirtualSize(session, vdi)
	check(err)
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var destSR xenapi.SRRef
	found := false
	for ref, sr := range srs {
		if ref == sourceSR || sr.ContentType == "iso" || sr.Type == "iso" || sr.Type == "udev" {
			continue
		}
		reachable := false
		for _, pbdRef := range sr.PBDs {
			pbdHost, err := xenapi.PBD.GetHost(session, pbdRef)
			check(err)
			attached, err := xenapi.PBD.GetCurrentlyAttached(session, pbdRef)
			check(err)
			if pbdHost == host && attached {
				reachable = true
				break
			}
		}
		if !reachable {
			continue
		}
		check(xenapi.SR.Scan(session, ref))
		physicalSize, err := xenapi.SR.GetPhysicalSize(session, ref)
		check(err)
		utilisation, err := xenapi.SR.GetPhysicalUtilisation(session, ref)
		check(err)
		if physicalSize-utilisation >= 2*size {
			destSR, found = ref, true
			break
		}
	}
	if !found {
		hostName, _ := xenapi.Host.GetNameLabel(session, host)
		check(xenapi.VM.HardShutdown(session, vm))
		destroyVMAndDisks(session, vm)
		panic(fmt.Sprintf("no other SR attached to %s has room for the %d GiB disk twice over", hostName, size/GiB))
	}

	// PoolMigrate returns the disk's new VDI: the copy on the destination SR replaces the original.
	vdi, err = xenapi.VDI.PoolMigrate(session, vdi, destSR, map[string]string{})
	check(err)

	nowOn, _ := xenapi.VDI.GetSR(session, vdi)
	nowName, _ := xenapi.SR.GetNameLabel(session, nowOn)
	fmt.Printf("Disk moved to:  %s\n", nowName)

	// Tidy up: the VM and the disks it now owns.
	check(xenapi.VM.HardShutdown(session, vm))
	destroyVMAndDisks(session, vm)
	fmt.Println("Cleaned up the example VM.")
	fmt.Println("OK: storage-migrate")
}
