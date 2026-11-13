package main

import (
	"fmt"

	"go/xenapi"
)

// convertToTemplate - Convert a VM to a template.
//
// Turn a VM into a reusable custom template. This is a one-way operation.
//
// Run it:
//
//	convertToTemplate("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-totemplate")
func convertToTemplate(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	vm, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vm) // now a real (halted) VM
	isTemplate, _ := xenapi.VM.GetIsATemplate(session, vm)
	fmt.Printf("is_a_template after provision: %v\n", isTemplate)

	// Converting a VM to a custom template is a one-way operation.
	check(xenapi.VM.SetIsATemplate(session, vm, true))
	isTemplate, _ = xenapi.VM.GetIsATemplate(session, vm)
	fmt.Printf("is_a_template after convert:  %v\n", isTemplate)

	destroyVMAndDisks(session, vm)
	fmt.Println("OK: convert-to-template")
	session.Logout()
}
