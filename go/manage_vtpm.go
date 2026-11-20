package main

import (
	"fmt"

	"go/xenapi"
)

// manageVtpm - Manage a virtual TPM.
//
// Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one,
// and only while it is halted.
func manageVtpm(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vm xenapi.VMRef
	var record xenapi.VMRecord
	found := false
	// vTPM is not supported for a BIOS-mode VM, only a UEFI one (HVM_boot_params["firmware"] ==
	// "uefi"), so pick one of those rather than any halted VM.
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && !v.IsASnapshot &&
			v.PowerState == xenapi.VMPowerStateHalted && len(v.VTPMs) == 0 &&
			v.HVMBootParams["firmware"] == "uefi" {
			vm, record, found = ref, v, true
			break
		}
	}
	if !found {
		panic("no halted UEFI VM without a vTPM already attached was found")
	}
	fmt.Printf("Attaching a vTPM to %s\n", record.NameLabel)

	// isUnique=false: the vTPM may be copied along with the VM. A VM may have at most one, and it can
	// only be attached while Halted — the device is presented at boot.
	vtpm, err := xenapi.VTPM.Create(session, vm, false)
	check(err)
	vtpmRecord, err := xenapi.VTPM.GetRecord(session, vtpm)
	check(err)
	fmt.Printf("  persistence backend: %s\n", vtpmRecord.PersistenceBackend)
	fmt.Printf("  unique to this VM:   %t\n", vtpmRecord.IsUnique)
	attached, err := xenapi.VM.GetVTPMs(session, vm)
	check(err)
	fmt.Printf("  VM now has %d vTPM(s)\n", len(attached))

	// The VM advertises whether another can be added; once it has one, it cannot.
	ops, err := xenapi.VM.GetAllowedOperations(session, vm)
	check(err)
	canAdd := false
	for _, op := range ops {
		if op == xenapi.VMOperationsCreateVtpm {
			canAdd = true
		}
	}
	fmt.Printf("  can add another:     %t\n", canAdd)

	check(xenapi.VTPM.Destroy(session, vtpm))
	attached, err = xenapi.VM.GetVTPMs(session, vm)
	check(err)
	fmt.Printf("  after removal:       %d vTPM(s)\n", len(attached))
	fmt.Println("OK: manage-vtpm")
}
