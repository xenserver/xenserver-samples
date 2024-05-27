package testGoSDK

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"xenapi"
)

func TestNFSSRCreateAndDestroy(t *testing.T) {
	if *NFS_SERVER_FLAG == "" || *NFS_PATH_FLAG == "" {
		t.Log("NFS server or path is not provided, skipping NFS SR test")
		t.Fail()
		return
	}

	// Choose the first host
	hostRefs, err := xenapi.Host.GetAll(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	hostName, err := xenapi.Host.GetNameLabel(session, hostRefs[0])
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Got host :", hostName)

	// Create config parameter for shared storage on nfs server
	var deviceConfig = make(map[string]string)
	deviceConfig["server"] = *NFS_SERVER_FLAG
	deviceConfig["serverpath"] = *NFS_PATH_FLAG

	t.Log("Creating a shared storage SR ...")
	var srRefNew xenapi.SRRef
	srRefNew, err = xenapi.SR.Create(session, hostRefs[0], deviceConfig, 100000, "NFS SR created by sr_nfs_test.go",
		fmt.Sprintf("[%s:%s] Created at %s", *NFS_SERVER_FLAG, *NFS_PATH_FLAG, time.Now().String()), "nfs", "unused",
		true, make(map[string]string))
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	err = WaitForSRReady(session, srRefNew)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	err = xenapi.SR.SetNameDescription(session, srRefNew, "New description")
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	t.Log("Now unplugging PBDs")
	pbdRefs, err := xenapi.SR.GetPBDs(session, srRefNew)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	for _, pbdRef := range pbdRefs {
		pbdRecord, err := xenapi.PBD.GetRecord(session, pbdRef)
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
		if pbdRecord.CurrentlyAttached {
			err = xenapi.PBD.Unplug(session, pbdRef)
			if err != nil {
				t.Log(err)
				t.Fail()
				return
			}
		}
	}

	t.Log("Now destroying the newly-created SR")
	err = xenapi.SR.Destroy(session, srRefNew)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	// try a couple of erroneous calls to generate exceptions
	t.Log("Trying to create one with bad device_config")
	_, err = xenapi.SR.Create(session, hostRefs[0], make(map[string]string), 100000, "bad_device_config",
		"description", "nfs", "contenttype", true, make(map[string]string))
	if err == nil || !strings.Contains(err.Error(), "missing") {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("Trying to create one with a bad 'type' field")
	_, err = xenapi.SR.Create(session, hostRefs[0], make(map[string]string), 100000, "bad_sr_type",
		"description", "made_up", "", true, make(map[string]string))
	if err == nil || !strings.Contains(err.Error(), "made_up") {
		t.Log(err)
		t.Fail()
		return
	}
}
