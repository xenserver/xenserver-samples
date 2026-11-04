package main

import (
	"fmt"

	"go/xenapi"
)

// deleteVM - Delete a VM.
//
// Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are
// destroyed explicitly afterward.
//
// Run it:
//
//	deleteVM("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-delete")
func deleteVM(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	// Make a throwaway VM to delete. VM.Destroy removes the VM but leaves its disks, so the
	// owned VDIs are destroyed explicitly afterward - exactly what XenCenter's Delete VM does.
	vm, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vm)
	uuid, _ := xenapi.VM.GetUUID(session, vm)
	vdis := diskVdis(session, vm)
	fmt.Printf("Deleting VM %s with %d disk(s)\n", uuid, len(vdis))

	check(xenapi.VM.Destroy(session, vm))
	for _, vdi := range vdis {
		check(xenapi.VDI.Destroy(session, vdi))
	}

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	stillThere := false
	for _, v := range vms {
		if v.UUID == uuid {
			stillThere = true
			break
		}
	}
	fmt.Printf("VM still present: %v\n", stillThere)
	fmt.Println("OK: delete-vm")
	session.Logout()
}
