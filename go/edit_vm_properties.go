package main

import (
	"fmt"

	"go/xenapi"
)

// editVMProperties - Edit VM properties.
//
// Change a VM's description and custom metadata, then read the changes back.
//
// Run it:
//
//	editVMProperties("https://xenserver", "root", password, "web-01")
func editVMProperties(url, user, password, vmName string) {
	session := connect(url, user, password)
	vmRef := vmByName(session, vmName)

	originalDesc, _ := xenapi.VM.GetNameDescription(session, vmRef)
	check(xenapi.VM.SetNameDescription(session, vmRef, "Edited by the SDK example"))
	check(xenapi.VM.AddToOtherConfig(session, vmRef, "sdk_example", "true"))
	desc, _ := xenapi.VM.GetNameDescription(session, vmRef)
	fmt.Printf("New description: %s\n", desc)
	oc, _ := xenapi.VM.GetOtherConfig(session, vmRef)
	fmt.Printf("other_config[sdk_example] = %s\n", oc["sdk_example"])

	check(xenapi.VM.SetNameDescription(session, vmRef, originalDesc))
	check(xenapi.VM.RemoveFromOtherConfig(session, vmRef, "sdk_example"))
	fmt.Println("OK: edit-vm-properties")
	session.Logout()
}
