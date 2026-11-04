package main

import (
	"fmt"

	"go/xenapi"
)

// newVMWizard - Create a VM (full workflow).
//
// Create a VM end to end: pick a template, name the VM, choose an installation source and a home
// server, set CPU & memory, add a disk on a storage repository, attach a network interface and
// start it — the full sequence, rather than a single clone call.
//
// Run it:
//
//	newVMWizard("https://xenserver", "root", password, "Rocky Linux 8", "wizard-vm")
func newVMWizard(url, user, password, templateName, newVMName string) {
	const GiB = 1024 * 1024 * 1024
	const MiB = 1024 * 1024

	session := connect(url, user, password)
	// Page 1 - Template.
	templateRef := templateByName(session, templateName)
	tname, _ := xenapi.VM.GetNameLabel(session, templateRef)
	fmt.Printf("Template:      %s\n", tname)

	// Page 2 - Name and description.
	vm, err := xenapi.VM.Clone(session, templateRef, newVMName)
	check(err)
	check(xenapi.VM.SetNameDescription(session, vm, "Created by the full New VM wizard example"))
	check(xenapi.VM.SetIsATemplate(session, vm, false))
	uuid, _ := xenapi.VM.GetUUID(session, vm)
	fmt.Printf("Created VM:    %s\n", uuid)

	// Page 3 - Installation media (a network install repository).
	check(xenapi.VM.AddToOtherConfig(session, vm, "install-repository",
		"http://mirror.example.com/rocky/9/os/x86_64"))
	fmt.Println("Install media: network repository")

	// Page 4 - Home server (affinity).
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var hostRef xenapi.HostRef
	var hostName string
	for ref, h := range hosts {
		hostRef, hostName = ref, h.NameLabel
		break
	}
	check(xenapi.VM.SetAffinity(session, vm, hostRef))
	fmt.Printf("Home server:   %s\n", hostName)

	// Page 5 - CPU & Memory.
	check(xenapi.VM.SetVCPUsMax(session, vm, 2))
	check(xenapi.VM.SetVCPUsAtStartup(session, vm, 2))
	check(xenapi.VM.SetMemoryLimits(session, vm, 512*MiB, 2*GiB, 2*GiB, 2*GiB))
	fmt.Println("CPU/memory:    2 vCPUs, 2 GiB")

	// Page 6 - Storage: add a disk on a (non-ISO) SR.
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var srRef xenapi.SRRef
	var srName string
	for ref, sr := range srs {
		if sr.ContentType != "iso" && sr.Type != "iso" && sr.Type != "udev" {
			srRef, srName = ref, sr.NameLabel
			break
		}
	}
	vbdDevices, err := xenapi.VM.GetAllowedVBDDevices(session, vm)
	check(err)
	vdi, err := xenapi.VDI.Create(session, xenapi.VDIRecord{
		NameLabel:       newVMName + " disk 0",
		NameDescription: "System disk created by the wizard example",
		SR:              srRef,
		VirtualSize:     24 * GiB,
		Type:            xenapi.VdiTypeSystem,
		Sharable:        false,
		ReadOnly:        false,
		OtherConfig:     map[string]string{},
	})
	check(err)
	_, err = xenapi.VBD.Create(session, xenapi.VBDRecord{
		VM: vm, VDI: vdi, Userdevice: vbdDevices[0], Bootable: true,
		Mode: xenapi.VbdModeRW, Type: xenapi.VbdTypeDisk, Empty: false,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
	})
	check(err)
	fmt.Printf("Storage:       24 GiB disk on %s\n", srName)

	// Page 7 - Networking: attach a VIF to a network.
	nets, err := xenapi.Network.GetAllRecords(session)
	check(err)
	var netRef xenapi.NetworkRef
	var netName string
	for ref, n := range nets {
		netRef, netName = ref, n.NameLabel
		break
	}
	vifDevices, err := xenapi.VM.GetAllowedVIFDevices(session, vm)
	check(err)
	// A Go record sends every field, enums included, and a real host rejects an empty enum value
	// (INTERNAL_ERROR "Unknown tag/contents"), so set the enums to the defaults xapi applies when
	// they are left out.
	_, err = xenapi.VIF.Create(session, xenapi.VIFRecord{
		VM: vm, Network: netRef, Device: vifDevices[0], MAC: "", MTU: 1500,
		OtherConfig: map[string]string{}, QosAlgorithmParams: map[string]string{},
		LockingMode:           xenapi.VifLockingModeNetworkDefault,
		Ipv4ConfigurationMode: xenapi.VifIpv4ConfigurationModeNone,
		Ipv6ConfigurationMode: xenapi.VifIpv6ConfigurationModeNone,
	})
	check(err)
	fmt.Printf("Networking:    NIC on %s\n", netName)

	// Page 8 - Finish: start the VM.
	check(xenapi.VM.Start(session, vm, false, true))

	fmt.Println("--- Result ---")
	ps, _ := xenapi.VM.GetPowerState(session, vm)
	vcpus, _ := xenapi.VM.GetVCPUsMax(session, vm)
	vbds, _ := xenapi.VM.GetVBDs(session, vm)
	vifs, _ := xenapi.VM.GetVIFs(session, vm)
	fmt.Printf("power state:   %s\n", ps)
	fmt.Printf("vCPUs:         %d\n", vcpus)
	fmt.Printf("disks:         %d, NICs: %d\n", len(vbds), len(vifs))

	// Tidy up so the example is repeatable.
	check(xenapi.VM.HardShutdown(session, vm))
	check(xenapi.VM.Destroy(session, vm))
	check(xenapi.VDI.Destroy(session, vdi))
	fmt.Println("Cleaned up the example VM.")

	fmt.Println("OK: new-vm-wizard")
	session.Logout()
}
