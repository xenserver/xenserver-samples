package main

import (
	"fmt"

	"go/xenapi"
)

// attachUsbDevice - Attach a USB device to a VM.
//
// List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it
// again.
func attachUsbDevice(url, user, password, vmName string) {
	session := connect(url, user, password)
	vms, err := xenapi.VM.GetByNameLabel(session, vmName)
	check(err)
	vm := vms[0]

	pusbs, err := xenapi.PUSB.GetAllRecords(session)
	check(err)
	var pusbRef xenapi.PUSBRef
	var pusb xenapi.PUSBRecord
	for ref, rec := range pusbs {
		pusbRef, pusb = ref, rec
		break
	}
	fmt.Printf("Device:         %s\n", pusb.Description)

	// Passthrough is off until an administrator releases the device: attaching one that has not been
	// released fails rather than silently doing nothing.
	check(xenapi.PUSB.SetPassthroughEnabled(session, pusbRef, true))

	vusb, err := xenapi.VUSB.Create(session, vm, pusb.USBGroup, map[string]string{})
	check(err)
	attached, _ := xenapi.VM.GetVUSBs(session, vm)
	fmt.Printf("Attached:       %d device(s)\n", len(attached))

	// VUSB.Destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM
	// it gets plugged in as soon as it's created, so unplug it first.
	vusbRecord, err := xenapi.VUSB.GetRecord(session, vusb)
	check(err)
	if vusbRecord.CurrentlyAttached {
		check(xenapi.VUSB.Unplug(session, vusb))
	}
	check(xenapi.VUSB.Destroy(session, vusb))
	check(xenapi.PUSB.SetPassthroughEnabled(session, pusbRef, false))
	fmt.Println("OK: attach-usb-device")
	session.Logout()
}
