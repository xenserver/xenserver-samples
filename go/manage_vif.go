package main

import (
	"fmt"

	"go/xenapi"
)

// manageVif - Manage network interfaces.
//
// Attach a virtual network interface to a VM and remove it again.
//
// Run it:
//
//	manageVif("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vif")
func manageVif(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	vm, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vm)
	nets, err := xenapi.Network.GetAll(session)
	check(err)
	netRef := nets[0]
	devices, err := xenapi.VM.GetAllowedVIFDevices(session, vm)
	check(err)
	device := devices[0]

	// A Go record sends every field, enums included, and a real host rejects an empty enum value
	// (INTERNAL_ERROR "Unknown tag/contents"), so set the enums to the defaults xapi applies when
	// they are left out.
	vif, err := xenapi.VIF.Create(session, xenapi.VIFRecord{
		VM: vm, Network: netRef, Device: device, MAC: "", MTU: 1500,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
		LockingMode:           xenapi.VifLockingModeNetworkDefault,
		Ipv4ConfigurationMode: xenapi.VifIpv4ConfigurationModeNone,
		Ipv6ConfigurationMode: xenapi.VifIpv6ConfigurationModeNone,
	})
	check(err)
	vifs, _ := xenapi.VM.GetVIFs(session, vm)
	fmt.Printf("Attached a VIF on device %s; VM now has %d NIC(s)\n", device, len(vifs))

	check(xenapi.VIF.Destroy(session, vif))
	destroyVMAndDisks(session, vm)
	fmt.Println("OK: manage-vif")
	session.Logout()
}
