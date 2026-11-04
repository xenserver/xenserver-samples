package main

import (
	"fmt"

	"go/xenapi"
)

// manageVapp - Manage a vApp.
//
// Group VMs into an appliance that starts and stops together in a defined order, start and shut it
// down as a unit, then remove it.
func manageVapp(url, user, password, vmName string) {
	session := connect(url, user, password)
	vms, err := xenapi.VM.GetByNameLabel(session, vmName)
	check(err)
	vm := vms[0]

	vapp, err := xenapi.VMAppliance.Create(session, xenapi.VMApplianceRecord{
		NameLabel:       "sdk-example-vapp",
		NameDescription: "Created by the SDK example",
	})
	check(err)

	// `order` decides the sequence: ascending to start, descending to shut down. That ordering is the
	// reason to use a vApp rather than selecting several VMs.
	check(xenapi.VM.SetAppliance(session, vm, vapp))
	check(xenapi.VM.SetOrder(session, vm, 0))
	check(xenapi.VM.SetStartDelay(session, vm, 5))

	check(xenapi.VMAppliance.Start(session, vapp, false))
	state, _ := xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Started:        %s\n", state)

	// Shutdown tries each VM's clean shutdown and falls back to a hard one. CleanShutdown alone fails
	// OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers).
	check(xenapi.VMAppliance.Shutdown(session, vapp))
	state, _ = xenapi.VM.GetPowerState(session, vm)
	fmt.Printf("Shut down:      %s\n", state)

	check(xenapi.VM.SetAppliance(session, vm, ""))
	check(xenapi.VMAppliance.Destroy(session, vapp))
	fmt.Println("OK: manage-vapp")
	session.Logout()
}
