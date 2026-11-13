package main

import (
	"fmt"

	"go/xenapi"
)

// attachDisk - Attach a new disk.
//
// Create a fresh virtual disk on a storage repository and attach it to a VM.
//
// Run it:
//
//	attachDisk("https://xenserver", "root", password, "Rocky Linux 8", "Shared NFS", "sdk-example-attachdisk")
func attachDisk(url, user, password, templateName, srName, newVMName string) {
	const GiB = 1024 * 1024 * 1024

	session := connect(url, user, password)
	vm, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vm)
	srRef := srByName(session, srName, false)

	// Create a fresh VDI on the SR and attach it as a new VBD (a new virtual disk).
	vdi, err := xenapi.VDI.Create(session, xenapi.VDIRecord{
		NameLabel:   "sdk-example-data-disk",
		SR:          srRef,
		VirtualSize: 8 * GiB,
		Type:        xenapi.VdiTypeUser,
		Sharable:    false,
		ReadOnly:    false,
		OtherConfig: map[string]string{},
	})
	check(err)
	devices, err := xenapi.VM.GetAllowedVBDDevices(session, vm)
	check(err)
	device := devices[0]
	_, err = xenapi.VBD.Create(session, xenapi.VBDRecord{
		VM: vm, VDI: vdi, Userdevice: device,
		Bootable: false,
		Mode:     xenapi.VbdModeRW, Type: xenapi.VbdTypeDisk, Empty: false,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
	})
	check(err)
	srLabel, _ := xenapi.SR.GetNameLabel(session, srRef)
	fmt.Printf("Attached an 8 GiB disk on %s as device %s\n", srLabel, device)
	vbds, _ := xenapi.VM.GetVBDs(session, vm)
	fmt.Printf("VM now has %d VBD(s)\n", len(vbds))

	// Tidy up: destroy the VM (which removes its VBDs) and then its disks (VM.Destroy leaves VDIs
	// behind), including the one just attached.
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: attach-disk")
	session.Logout()
}
