package main

import (
	"fmt"

	"go/xenapi"
)

// manageVMDisks - Manage VM disks.
//
// Deactivate a running VM's disk, resize it, reactivate it.
//
// A real VM's root/boot disk is unpluggable=false (only non-system disks from VM.Provision default
// to unpluggable), and the VM has to be Running for VBD.Unplug to be legal at all
// (VM_BAD_POWER_STATE otherwise on a halted VM). So this works on a NEW data disk added to a
// throwaway VM of its own. No shrink demonstration: real SR backends refuse one outright
// (SR_BACKEND_FAILURE_79).
//
// Plugging and unplugging a disk on a running VM needs the guest's PV drivers
// (VM_MISSING_PV_DRIVERS otherwise), so the VM is a throwaway copy of sourceVM, a VM with a guest OS
// and PV drivers.
func manageVMDisks(url, user, password, sourceVM, srName, newVMName string) {
	const GiB = 1024 * 1024 * 1024
	session := connect(url, user, password)
	vmRef := copyOfGuest(session, sourceVM, newVMName)
	check(xenapi.VM.Start(session, vmRef, false, true))
	waitForGuestAgent(session, vmRef)

	srRef := srByName(session, srName, false)
	vdiRef, err := xenapi.VDI.Create(session, xenapi.VDIRecord{
		NameLabel:   "sdk-example-data-disk",
		SR:          srRef,
		VirtualSize: 4 * GiB,
		Type:        xenapi.VdiTypeUser,
		Sharable:    false,
		ReadOnly:    false,
		OtherConfig: map[string]string{},
	})
	check(err)
	devices, err := xenapi.VM.GetAllowedVBDDevices(session, vmRef)
	check(err)
	vbdRef, err := xenapi.VBD.Create(session, xenapi.VBDRecord{
		VM: vmRef, VDI: vdiRef, Userdevice: devices[0],
		Bootable: false,
		Mode:     xenapi.VbdModeRW, Type: xenapi.VbdTypeDisk, Empty: false,
		// A Go record sends every field, so say so explicitly: a VBD created with unpluggable=false
		// can't be hot-unplugged (VBD_NOT_UNPLUGGABLE). xapi's own default, when the field is left
		// out, is true.
		Unpluggable: true,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
	})
	check(err)
	check(xenapi.VBD.Plug(session, vbdRef))
	attached, _ := xenapi.VBD.GetCurrentlyAttached(session, vbdRef)
	fmt.Printf("Disk attached:  %t\n", attached)

	// Deactivate = VBD.unplug. The disk stays with the VM; it is just no longer live.
	check(xenapi.VBD.Unplug(session, vbdRef))
	attached, _ = xenapi.VBD.GetCurrentlyAttached(session, vbdRef)
	fmt.Printf("After unplug:   %t\n", attached)

	size, err := xenapi.VDI.GetVirtualSize(session, vdiRef)
	check(err)
	check(xenapi.VDI.Resize(session, vdiRef, size*2))
	grown, _ := xenapi.VDI.GetVirtualSize(session, vdiRef)
	fmt.Printf("Resized:        %d -> %d bytes\n", size, grown)

	check(xenapi.VBD.Plug(session, vbdRef))
	attached, _ = xenapi.VBD.GetCurrentlyAttached(session, vbdRef)
	fmt.Printf("After plug:     %t\n", attached)

	// Growing a disk that is attached and live is a DIFFERENT call, not a flag on the same one:
	// ResizeOnline tells the storage layer the guest is using the disk while it grows. Only some
	// storage drivers can (none of a stock XenServer 9's do), and the rest refuse with
	// SR_OPERATION_NOT_SUPPORTED - so ask the SR's driver (its SM record's features) first.
	srType, err := xenapi.SR.GetType(session, srRef)
	check(err)
	sms, err := xenapi.SM.GetAllRecords(session)
	check(err)
	resizeOnline := false
	for _, sm := range sms {
		if sm.Type == srType {
			_, resizeOnline = sm.Features["VDI_RESIZE_ONLINE"]
			break
		}
	}
	if resizeOnline {
		grownOnline := grown + GiB
		check(xenapi.VDI.ResizeOnline(session, vdiRef, grownOnline))
		final, _ := xenapi.VDI.GetVirtualSize(session, vdiRef)
		fmt.Printf("Grown online:   %d bytes\n", final)
	} else {
		fmt.Printf("Grown online:   not supported by %s storage; unplug, resize, plug as above\n", srType)
	}

	check(xenapi.VM.HardShutdown(session, vmRef))
	destroyVMAndDisks(session, vmRef)
	fmt.Println("OK: manage-vm-disks")
	session.Logout()
}
