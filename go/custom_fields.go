package main

import (
	"fmt"

	"go/xenapi"
)

// customFields - Custom fields.
//
// Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the
// object.
//
// Run it:
//
//	customFields("https://xenserver", "root", password, "web-01")
func customFields(url, user, password, vmName string) {
	session := connect(url, user, password)
	// XenCenter's custom fields are stored in other_config under "XenCenter.CustomFields.<name>".
	vm := vmByName(session, vmName)
	const key = "XenCenter.CustomFields.Owner"
	check(xenapi.VM.AddToOtherConfig(session, vm, key, "Platform Team"))
	oc, _ := xenapi.VM.GetOtherConfig(session, vm)
	fmt.Printf("Custom field Owner = %s\n", oc[key])

	check(xenapi.VM.RemoveFromOtherConfig(session, vm, key))
	fmt.Println("OK: custom-fields")
	session.Logout()
}
