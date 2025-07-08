package testGoSDK

import (
	"testing"

	"xenapi"
)

func TestVMSnapshot(t *testing.T) {
	if stopTests {
		t.Skip("Skipping due to login failure")
	}

	vmRefTest, err := FindHaltedLinuxVM()
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if vmRefTest == "" {
		t.Log("No halted Linux VM found.")
		t.Fail()
		return
	}

	// Snapshot Type 1 Disk
	var snapshotRef xenapi.VMRef
	if session.APIVersion >= xenapi.APIVersion2_21 {
		snapshotRef, err = xenapi.VM.Snapshot(session, vmRefTest, "Snapshot1", []xenapi.VDIRef{})
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
	} else {
		snapshotRef, err = xenapi.VM.Snapshot3(session, vmRefTest, "Snapshot1")
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
	}
	snapshotRecord, err := xenapi.VM.GetRecord(session, snapshotRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if snapshotRecord.SnapshotOf != vmRefTest {
		t.Log("Snapshot1 is not snapshot of test Linux VM:", vmRefTest)
		t.Fail()
		return
	}
	err = xenapi.VM.Revert(session, snapshotRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	err = xenapi.VM.Destroy(session, snapshotRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	snapshotRefs, err := xenapi.VM.GetSnapshots(session, vmRefTest)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if len(snapshotRefs) != 0 {
		t.Log("Delete snapshot error.")
		t.Fail()
		return
	}
}

func TestVMAsyncSnapshot(t *testing.T) {
	if stopTests {
		t.Skip("Skipping due to login failure")
	}

	vmRefTest, err := FindHaltedLinuxVM()
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if vmRefTest == "" {
		t.Log("No halted Linux VM found.")
		t.Fail()
		return
	}

	// Snapshot Type 2 Disk and memory
	vmRecordTest, err := xenapi.VM.GetRecord(session, vmRefTest)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if vmRecordTest.PowerState == xenapi.VMPowerStateHalted {
		if vmRecordTest.ResidentOn == "OpaqueRef:NULL" {
			taskRef, err := xenapi.VM.AsyncStart(session, vmRefTest, true, true)
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
		} else {
			taskRef, err := xenapi.VM.AsyncAssertCanBootHere(session, vmRefTest, vmRecordTest.ResidentOn)
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
			taskRef, err = xenapi.VM.AsyncStartOn(session, vmRefTest, vmRecordTest.ResidentOn, true, true)
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
		}
	} else if vmRecordTest.PowerState == xenapi.VMPowerStateSuspended {
		if vmRecordTest.ResidentOn == "OpaqueRef:NULL" {
			taskRef, err := xenapi.VM.AsyncResume(session, vmRefTest, true, true)
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
		} else {
			taskRef, err := xenapi.VM.AsyncAssertCanBootHere(session, vmRefTest, vmRecordTest.ResidentOn)
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
			taskRef, err = xenapi.VM.AsyncResumeOn(session, vmRefTest, vmRecordTest.ResidentOn, true, true)
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
		}
	}
	taskRef, err := xenapi.VM.AsyncCheckpoint(session, vmRefTest, "Snapshot2")
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
	snapshotRefs, err := xenapi.VM.GetSnapshots(session, vmRefTest)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if len(snapshotRefs) == 0 {
    	t.Log("No snapshots found for this VM")
		t.Fail()
		return
	}
	snapshotName, err := xenapi.VM.GetNameLabel(session, snapshotRefs[0])
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if snapshotName != "Snapshot2" {
		t.Log("Snapshot2 is not found.")
		t.Fail()
		return
	}
	taskRef, err = xenapi.VM.AsyncRevert(session, snapshotRefs[0])
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
	err = xenapi.VM.Destroy(session, snapshotRefs[0])
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
}
