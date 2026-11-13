package main

import (
	"fmt"

	"go/xenapi"
)

// vbdInventory - Inventory a VM's disks.
//
// List a VM's attached disks and the size of each.
//
// Run it:
//
//	vbdInventory("https://xenserver", "root", password, "db-01")
func vbdInventory(url, user, password, vmName string) {
	const GiB = 1024 * 1024 * 1024

	session := connect(url, user, password)
	vm := vmByName(session, vmName)
	name, _ := xenapi.VM.GetNameLabel(session, vm)
	fmt.Printf("Disks of '%s':\n", name)
	vbds, err := xenapi.VM.GetVBDs(session, vm)
	check(err)
	for _, vbdRef := range vbds {
		vbd, err := xenapi.VBD.GetRecord(session, vbdRef)
		check(err)
		if vbd.Type != xenapi.VbdTypeDisk {
			continue
		}
		vdi, _ := xenapi.VBD.GetVDI(session, vbdRef)
		var size int64
		if isSet(vdi) {
			virtualSize, _ := xenapi.VDI.GetVirtualSize(session, vdi)
			size = virtualSize / GiB
		}
		fmt.Printf("  - device %s: %d GiB\n", vbd.Userdevice, size)
	}
	fmt.Println("OK: vbd-inventory")
	session.Logout()
}
