package testGoSDK

import (
	"strings"
	"testing"

	"xenapi"
)

var NEW_VM_NAME = "GoSDK-TestVM"

func TestVMCreateAndDestroy(t *testing.T) {
	if stopTests {
		t.Skip("Skipping due to login failure")
	}
	// Find a template
	templateRef, templateName, err := GetFirstTemplate("Windows")
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Template found:", templateName)

	// Clone the VM template
	t.Log("Cloning the template...")
	vmRef, err := xenapi.VM.Clone(session, templateRef, NEW_VM_NAME)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	vmRecord, err := xenapi.VM.GetRecord(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("New VM clone:", vmRecord.NameLabel)

	// Find a storage repository
	srRef, err := GetStorage()
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	srRecord, err := xenapi.SR.GetRecord(session, srRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Found SR:", srRecord.NameLabel)

	// Find a network
	networkRef, err := GetFirstNetwork()
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	networkRecord, err := xenapi.Network.GetRecord(session, networkRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Network chosen:", networkRecord.NameLabel)

	// Make a VIF
	t.Log("Creating a VIF...")
	var vifRecord xenapi.VIFRecord
	vifRecord.VM = vmRef
	vifRecord.Network = networkRef
	vifRecord.Device = "0"
	vifRecord.MTU = 1500
	vifRecord.LockingMode = xenapi.VifLockingModeNetworkDefault
	_, err = xenapi.VIF.Create(session, vifRecord)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Vif created")

	// Put the SR uuid into the provision XML
	otherConfig, err := xenapi.VM.GetOtherConfig(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	disks, ok := otherConfig["disks"]
	if !ok {
		t.Log("No disks found.")
		t.Fail()
		return
	}
	srUuid, err := xenapi.SR.GetUUID(session, srRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	disks = strings.Replace(disks, "sr=\"\"", "sr=\""+srUuid+"\"", -1)
	otherConfig["disks"] = disks
	err = xenapi.VM.SetOtherConfig(session, vmRef, otherConfig)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	var vbdRecord xenapi.VBDRecord
	vbdRecord.VM = vmRef
	vbdRecord.VDI = ""
	vbdRecord.Userdevice = "3"
	vbdRecord.Mode = xenapi.VbdModeRO
	vbdRecord.Type = xenapi.VbdTypeCD
	vbdRecord.Empty = true
	_, err = xenapi.VBD.Create(session, vbdRecord)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VBD created")

	// Now provision the disks
	t.Log("provisioning... ")
	err = xenapi.VM.Provision(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("provisioned.")

	// Should have done the trick. Let's see if it starts.
	err = xenapi.VM.Start(session, vmRef, false, false)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Started.")

	err = xenapi.VM.HardShutdown(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Shut down.")

	err = xenapi.VM.Destroy(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Destroyed.")
}

func TestVMAsyncCreateAndDestroy(t *testing.T) {
	if stopTests {
		t.Skip("Skipping due to login failure")
	}
	// Find a template
	templateRef, templateName, err := GetFirstTemplate("Windows")
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Template found:", templateName)

	// Clone the VM template
	t.Log("Cloning the template...")
	taskRef, err := xenapi.VM.AsyncClone(session, templateRef, NEW_VM_NAME)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	err = WaitForTask(taskRef, 1)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	vmRefs, err := xenapi.VM.GetByNameLabel(session, NEW_VM_NAME)
	vmRecord, err := xenapi.VM.GetRecord(session, vmRefs[0])
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("New VM clone:", vmRecord.NameLabel)

	// Find a storage repository
	srRef, err := GetStorage()
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	srRecord, err := xenapi.SR.GetRecord(session, srRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Found SR:", srRecord.NameLabel)

	// Find a network
	networkRef, err := GetFirstNetwork()
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	networkRecord, err := xenapi.Network.GetRecord(session, networkRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Network chosen:", networkRecord.NameLabel)

	// Make a VIF
	t.Log("Creating a VIF...")
	var vifRecord xenapi.VIFRecord
	vifRecord.VM = vmRefs[0]
	vifRecord.Network = networkRef
	vifRecord.Device = "0"
	vifRecord.MTU = 1500
	vifRecord.LockingMode = xenapi.VifLockingModeNetworkDefault
	taskRef, err = xenapi.VIF.AsyncCreate(session, vifRecord)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	err = WaitForTask(taskRef, 1)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Vif created")

	// Put the SR uuid into the provision XML
	otherConfig, err := xenapi.VM.GetOtherConfig(session, vmRefs[0])
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	disks, ok := otherConfig["disks"]
	if !ok {
		t.Log("No disks found.")
		t.Fail()
		return
	}
	srUuid, err := xenapi.SR.GetUUID(session, srRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	disks = strings.Replace(disks, "sr=\"\"", "sr=\""+srUuid+"\"", -1)
	otherConfig["disks"] = disks
	err = xenapi.VM.SetOtherConfig(session, vmRefs[0], otherConfig)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	var vbdRecord xenapi.VBDRecord
	vbdRecord.VM = vmRefs[0]
	vbdRecord.VDI = ""
	vbdRecord.Userdevice = "3"
	vbdRecord.Mode = xenapi.VbdModeRO
	vbdRecord.Type = xenapi.VbdTypeCD
	vbdRecord.Empty = true
	taskRef, err = xenapi.VBD.AsyncCreate(session, vbdRecord)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	err = WaitForTask(taskRef, 1)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VBD created")

	// Now provision the disks
	t.Log("provisioning... ")
	taskRef, err = xenapi.VM.AsyncProvision(session, vmRefs[0])
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	err = WaitForTask(taskRef, 1)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("provisioned.")

	// Should have done the trick. Let's see if it starts.
	taskRef, err = xenapi.VM.AsyncStart(session, vmRefs[0], false, false)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	err = WaitForTask(taskRef, 1)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Started.")

	taskRef, err = xenapi.VM.AsyncHardShutdown(session, vmRefs[0])
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	err = WaitForTask(taskRef, 1)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Shut down.")

	taskRef, err = xenapi.VM.AsyncDestroy(session, vmRefs[0])
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	err = WaitForTask(taskRef, 1)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Destroyed.")
}
