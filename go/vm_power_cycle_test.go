package testGoSDK

import (
	"fmt"
	"testing"
	"time"

	"xenapi"
)

func TestVMPowercycle(t *testing.T) {
	vmRefTest, err := FindHaltedLinuxVM()
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	//to avoid playing with existing data, clone the VM and powercycle its clone
	vmRecordTest, err := xenapi.VM.GetRecord(session, vmRefTest)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log(fmt.Sprintf("Cloning VM '%s'...", vmRecordTest.NameLabel))
	vmRef, err := xenapi.VM.Clone(session, vmRefTest, fmt.Sprintf("Cloned VM (from '%s')", vmRecordTest.NameLabel))
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Cloned VM; new VM's ref is", vmRef)

	err = xenapi.VM.SetNameDescription(session, vmRef, "Another cloned VM")
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
	t.Log(fmt.Sprintf("Clone VM's Name: %s, Description: %s, Power State: %s", vmRecord.NameLabel, vmRecord.NameDescription, vmRecord.PowerState))

	t.Log("Starting VM in paused state...")
	err = xenapi.VM.Start(session, vmRef, true, true)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	powerState, err := xenapi.VM.GetPowerState(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Power State: ", powerState)

	t.Log("Unpausing VM...")
	err = xenapi.VM.Unpause(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	powerState, err = xenapi.VM.GetPowerState(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Power State: ", powerState)

	// here we need to delay for a bit until the suspend feature is written
	// in the guest metrics; this check should be enough for most guests;
	// let's try a certain number of times with sleeps of a few seconds inbetween
	max := 20
	delay := 10
	for i := 0; i < max; i++ {
		record, err := xenapi.VM.GetRecord(session, vmRef)
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
		metrics, err := xenapi.VMGuestMetrics.GetRecord(session, record.GuestMetrics)
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
		featureSuspend, ok := metrics.Other["feature-suspend"]
		if ok {
			if featureSuspend == "1" {
				break
			}
		}
		t.Log(fmt.Sprintf("Checked for feature-suspend count %d out of %d; will re-try in %d sec.", i+1, max, delay))
		time.Sleep(time.Duration(delay) * time.Second)
	}

	t.Log("Suspending VM...")
	err = xenapi.VM.Suspend(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	powerState, err = xenapi.VM.GetPowerState(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Power State: ", powerState)

	t.Log("Resuming VM...")
	err = xenapi.VM.Resume(session, vmRef, false, true)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	powerState, err = xenapi.VM.GetPowerState(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Power State: ", powerState)

	t.Log("Forcing shutdown VM...")
	err = xenapi.VM.HardShutdown(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	powerState, err = xenapi.VM.GetPowerState(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM Power State: ", powerState)

	t.Log("Destroying VM...")
	err = xenapi.VM.Destroy(session, vmRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("VM destroyed.")
}
