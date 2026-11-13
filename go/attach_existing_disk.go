package main

import (
	"fmt"

	"go/xenapi"
)

// attachExistingDisk - Attach an existing disk to another VM.
//
// Move a disk between VMs by detaching and re-attaching it, without copying the data.
func attachExistingDisk(url, user, password string) {
	const GiB = 1024 * 1024 * 1024
	session := connect(url, user, password)
	defer session.Logout()

	// A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk between VMs
	// is removing one VBD and creating another - no copying, and the data stays where it is.
	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var halted []xenapi.VMRef
	for ref, r := range vms {
		if !r.IsATemplate && !r.IsControlDomain && !r.IsASnapshot && r.PowerState == xenapi.VMPowerStateHalted {
			halted = append(halted, ref)
		}
	}

	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var sr xenapi.SRRef
	for ref, r := range srs {
		if r.Shared && r.ContentType != "iso" && r.Type != "iso" && r.Type != "udev" {
			sr = ref
			break
		}
	}
	vdi, err := xenapi.VDI.Create(session, xenapi.VDIRecord{
		NameLabel:   "sdk-example-portable-disk",
		SR:          sr,
		VirtualSize: 4 * GiB,
		Type:        xenapi.VdiTypeUser,
		OtherConfig: map[string]string{},
	})
	check(err)
	vdiName, _ := xenapi.VDI.GetNameLabel(session, vdi)
	srName, _ := xenapi.SR.GetNameLabel(session, sr)
	fmt.Printf("Disk %s created on %s\n", vdiName, srName)

	vbd := attachVdi(session, halted[0], vdi)
	firstName, _ := xenapi.VM.GetNameLabel(session, halted[0])
	fmt.Printf("  attached to %s\n", firstName)

	// Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
	check(xenapi.VBD.Destroy(session, vbd))
	size, _ := xenapi.VDI.GetVirtualSize(session, vdi)
	fmt.Printf("  detached:   the disk still exists (%d bytes)\n", size)

	attachVdi(session, halted[1], vdi)
	secondName, _ := xenapi.VM.GetNameLabel(session, halted[1])
	fmt.Printf("  attached to %s\n", secondName)
	vbds, _ := xenapi.VDI.GetVBDs(session, vdi)
	fmt.Printf("  the disk is on %d VM(s)\n", len(vbds))

	for _, ref := range vbds {
		check(xenapi.VBD.Destroy(session, ref))
	}
	check(xenapi.VDI.Destroy(session, vdi))
	fmt.Println("OK: attach-existing-disk")
}

// attachVdi joins an existing disk to a VM on its next free device slot.
func attachVdi(session *xenapi.Session, vm xenapi.VMRef, vdi xenapi.VDIRef) xenapi.VBDRef {
	devices, err := xenapi.VM.GetAllowedVBDDevices(session, vm)
	check(err)
	vbd, err := xenapi.VBD.Create(session, xenapi.VBDRecord{
		VM: vm, VDI: vdi, Userdevice: devices[0],
		Bootable: false,
		Mode:     xenapi.VbdModeRW, Type: xenapi.VbdTypeDisk, Empty: false,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
	})
	check(err)
	return vbd
}
