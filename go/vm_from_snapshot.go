package main

import (
	"fmt"

	"go/xenapi"
)

// vmFromSnapshot - Create a VM and a template from a snapshot.
//
// Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.
//
// Run it:
//
//	vmFromSnapshot("https://xenserver", "root", password, "db-01")
func vmFromSnapshot(url, user, password, vmName string) {
	session := connect(url, user, password)
	defer session.Logout()

	// A snapshot is a VM record with is_a_snapshot (and is_a_template) set, and cloning it gives a custom
	// template that stands on its own while the snapshot stays put.
	vm := vmByName(session, vmName)
	snapshot, err := xenapi.VM.Snapshot(session, vm, "sdk-example-source-snapshot", nil)
	check(err)
	fmt.Printf("Snapshot of %s taken\n", vmName)

	// A clone of a snapshot is a template, not another snapshot: it stands on its own instead of being
	// filed under the original VM. Provision it to get an ordinary VM you can start.
	newVM, err := xenapi.VM.Clone(session, snapshot, "sdk-example-vm-from-snapshot")
	check(err)
	provision(session, newVM)
	newName, _ := xenapi.VM.GetNameLabel(session, newVM)
	newIsTmpl, _ := xenapi.VM.GetIsATemplate(session, newVM)
	fmt.Printf("  new VM:      %s (is_a_template=%t)\n", newName, newIsTmpl)

	// Another clone, left as the template it already is: a starting point to stamp more VMs from.
	template, err := xenapi.VM.Clone(session, snapshot, "sdk-example-template-from-snapshot")
	check(err)
	tmplName, _ := xenapi.VM.GetNameLabel(session, template)
	isTmpl, _ := xenapi.VM.GetIsATemplate(session, template)
	fmt.Printf("  new template:%s (is_a_template=%t)\n", tmplName, isTmpl)

	// Each clone made its own disks, and the snapshot has its own snapshot disks; destroy them all.
	for _, ref := range []xenapi.VMRef{newVM, template, snapshot} {
		destroyVMAndDisks(session, ref)
	}
	fmt.Println("OK: vm-from-snapshot")
}
