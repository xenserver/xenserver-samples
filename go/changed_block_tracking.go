package main

import (
	"encoding/base64"
	"fmt"
	"math/bits"

	"go/xenapi"
)

// changedBlockTracking - Back up with changed block tracking.
//
// Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which
// blocks differ, then release the older snapshot's data while keeping the change metadata the next
// incremental needs.
func changedBlockTracking(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vm xenapi.VMRef
	var record xenapi.VMRecord
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && !v.IsASnapshot && len(v.VBDs) > 0 {
			vm, record = ref, v
			break
		}
	}
	fmt.Printf("Backing up %s\n", record.NameLabel)

	// CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it. It
	// can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
	live := firstDisk(session, vm)
	wasEnabled, err := xenapi.VDI.GetCbtEnabled(session, live)
	check(err)
	if !wasEnabled {
		check(xenapi.VDI.EnableCbt(session, live))
	}

	first, err := xenapi.VM.Snapshot(session, vm, "cbt-backup-1", nil)
	check(err)
	second, err := xenapi.VM.Snapshot(session, vm, "cbt-backup-2", nil)
	check(err)
	vdiFrom, vdiTo := firstDisk(session, first), firstDisk(session, second)

	// One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup reads
	// only those blocks, over NBD.
	encoded, err := xenapi.VDI.ListChangedBlocks(session, vdiFrom, vdiTo)
	check(err)
	bitmap, err := base64.StdEncoding.DecodeString(encoded)
	check(err)
	changed := 0
	for _, b := range bitmap {
		changed += bits.OnesCount8(b)
	}
	size, err := xenapi.VDI.GetVirtualSize(session, vdiTo)
	check(err)
	fmt.Printf("  %d blocks of %d changed (%.1f MiB to copy, not %.1f MiB)\n",
		changed, len(bitmap)*8, float64(changed)*64/1024, float64(size)/(1024*1024))

	// Release the older snapshot's blocks but keep its change metadata, so the next incremental can
	// still diff against it. DataDestroy refuses a disk that a VM still uses (VDI_IN_USE), so drop the
	// older snapshot's VM record first, as a backup tool does. The VDI record stays; its type changes.
	check(xenapi.VM.Destroy(session, first))
	check(xenapi.VDI.DataDestroy(session, vdiFrom))
	vdiType, err := xenapi.VDI.GetType(session, vdiFrom)
	check(err)
	stillTracked, err := xenapi.VDI.GetCbtEnabled(session, vdiFrom)
	check(err)
	fmt.Printf("  older snapshot is now type=%s, still cbt_enabled=%t\n", vdiType, stillTracked)

	// Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own disk if
	// this example switched it on.
	destroyVMAndDisks(session, second)
	check(xenapi.VDI.Destroy(session, vdiFrom))
	if !wasEnabled {
		check(xenapi.VDI.DisableCbt(session, live))
	}
	fmt.Println("OK: changed-block-tracking")
}

// firstDisk returns the VDI behind a VM's first real disk (a CD drive is a VBD too).
func firstDisk(session *xenapi.Session, vm xenapi.VMRef) xenapi.VDIRef {
	vbds, err := xenapi.VM.GetVBDs(session, vm)
	check(err)
	for _, vbd := range vbds {
		vbdType, err := xenapi.VBD.GetType(session, vbd)
		check(err)
		if vbdType == xenapi.VbdTypeDisk {
			vdi, err := xenapi.VBD.GetVDI(session, vbd)
			check(err)
			return vdi
		}
	}
	panic("no disk found")
}
