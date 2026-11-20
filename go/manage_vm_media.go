package main

import (
	"fmt"
	"sort"

	"go/xenapi"
)

// manageVMMedia - Manage a VM's CD drive.
//
// Add a DVD drive to a VM, insert an ISO from the library and eject it again.
func manageVMMedia(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vm xenapi.VMRef
	var record xenapi.VMRecord
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && !v.IsASnapshot &&
			v.PowerState == xenapi.VMPowerStateHalted {
			vm, record = ref, v
			break
		}
	}
	if vm == "" {
		panic("no halted VM to give a DVD drive to")
	}

	// Find an ISO image before changing the VM, so a pool without one fails before it does.
	// An ISO library is an SR of content type "iso"; its VDIs are the images. Take the first
	// library that holds any (a host's physical DVD drive is content type iso too, but type udev).
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var vdis []xenapi.VDIRef
	for ref, s := range srs {
		if s.ContentType == "iso" && s.Type != "udev" {
			vdis, err = xenapi.SR.GetVDIs(session, ref)
			check(err)
			if len(vdis) > 0 {
				break
			}
		}
	}
	if len(vdis) == 0 {
		panic("no ISO library with an image in it was found")
	}
	names := map[xenapi.VDIRef]string{}
	for _, v := range vdis {
		name, err := xenapi.VDI.GetNameLabel(session, v)
		check(err)
		names[v] = name
	}
	sort.Slice(vdis, func(i, j int) bool { return names[vdis[i]] < names[vdis[j]] })
	iso := vdis[0]

	fmt.Printf("Adding a DVD drive to %s\n", record.NameLabel)

	// A CD drive is a VBD like any other, distinguished by type=CD; the media is whichever VDI it points
	// at, and an empty drive points at none.
	devices, err := xenapi.VM.GetAllowedVBDDevices(session, vm)
	check(err)
	drive, err := xenapi.VBD.Create(session, xenapi.VBDRecord{
		VM:                 vm,
		VDI:                nullRef,
		Userdevice:         devices[0],
		Bootable:           false,
		Mode:               xenapi.VbdModeRO,
		Type:               xenapi.VbdTypeCD,
		Empty:              true,
		Unpluggable:        true,
		OtherConfig:        map[string]string{},
		QosAlgorithmParams: map[string]string{},
	})
	check(err)
	empty, err := xenapi.VBD.GetEmpty(session, drive)
	check(err)
	fmt.Printf("  drive %s is empty: %t\n", devices[0], empty)

	fmt.Printf("  inserting %s\n", names[iso])
	check(xenapi.VBD.Insert(session, drive, iso))

	loaded, err := xenapi.VBD.GetVDI(session, drive)
	check(err)
	empty, err = xenapi.VBD.GetEmpty(session, drive)
	check(err)
	fmt.Printf("  drive now holds %s (empty=%t)\n", names[loaded], empty)

	check(xenapi.VBD.Eject(session, drive))
	empty, err = xenapi.VBD.GetEmpty(session, drive)
	check(err)
	fmt.Printf("  after eject, empty=%t\n", empty)

	check(xenapi.VBD.Destroy(session, drive))
	fmt.Println("OK: manage-vm-media")
}
