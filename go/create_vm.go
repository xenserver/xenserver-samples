package main

import (
	"fmt"

	"go/xenapi"
)

// createVM - Create a VM from a template.
//
// Clone one of the built-in templates and provision the clone into a real, installable VM.
//
// Run it:
//
//	createVM("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vm")
func createVM(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	templateRef := templateByName(session, templateName)
	name, _ := xenapi.VM.GetNameLabel(session, templateRef)
	fmt.Printf("Using template: %s\n", name)

	vmRef, err := xenapi.VM.Clone(session, templateRef, newVMName)
	check(err)
	uuid, _ := xenapi.VM.GetUUID(session, vmRef)
	fmt.Printf("Cloned new VM: %s\n", uuid)

	provision(session, vmRef)
	isTemplate, _ := xenapi.VM.GetIsATemplate(session, vmRef)
	fmt.Printf("Provisioned. is_a_template = %v\n", isTemplate)

	destroyVMAndDisks(session, vmRef)
	fmt.Println("Cleaned up the example VM.")

	fmt.Println("OK: create-vm")
	session.Logout()
}
