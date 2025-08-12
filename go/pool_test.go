package testGoSDK

import (
	"strings"
	"testing"
	"time"

	"xenapi"
)

func TestPoolJoinAndEject(t *testing.T) {
	if stopTests {
		t.Skip("Skipping due to login failure")
	}
	if *IP1_FLAG == "" || *USERNAME1_FLAG == "" || *PASSWORD1_FLAG == "" {
		t.Skip("Supporter host ip, username or password is not provided, skipping pool test")
	}

	// get current Pool
	poolRefs, err := xenapi.Pool.GetAll(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if len(poolRefs) == 0 {
		t.Log("No pool found")
		t.Fail()
		return
	}
	poolRecord, err := xenapi.Pool.GetRecord(session, poolRefs[0])
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	// create another session
	session2 := xenapi.NewSession(&xenapi.ClientOpts{
		URL: GetURL(*IP1_FLAG, true),
	})
	_, err = session2.LoginWithPassword(*USERNAME1_FLAG, *PASSWORD1_FLAG, "1.0", "Go sdk test")
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	srRefs, err := xenapi.SR.GetAll(session2)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	for _, srRef := range srRefs {
		srRecord, err := xenapi.SR.GetRecord(session2, srRef)
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
		if srRecord.Shared {
			pbdRefs, err := xenapi.PBD.GetAll(session2)
			if err != nil {
				t.Log(err)
				t.Fail()
				return
			}
			for _, pbdRef := range pbdRefs {
				pbdSRRef, err := xenapi.PBD.GetSR(session2, pbdRef)
				if err != nil {
					t.Log(err)
					t.Fail()
					return
				}
				if srRef == pbdSRRef {
					err = xenapi.PBD.Unplug(session2, pbdRef)
					if err != nil {
						t.Log(err)
						t.Fail()
						return
					}
					err = xenapi.PBD.Destroy(session2, pbdRef)
					if err != nil {
						t.Log(err)
					}
				}
			}
			err = xenapi.SR.Forget(session2, srRef)
			if err != nil {
				t.Log(err)
				t.Fail()
				return
			}
		}
	}

	// add the host to the pool
	ip := strings.TrimPrefix(strings.TrimPrefix(*IP_FLAG, "http://"), "https://")
	_, err = xenapi.Pool.AsyncJoin(session2, ip, *USERNAME_FLAG, *PASSWORD_FLAG)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	time.Sleep(time.Duration(60) * time.Second)

	hostRefs, err := xenapi.Host.GetAll(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if len(hostRefs) != 2 {
		t.Log("Pool Join failed")
		t.Fail()
		return
	}
	var hostRefSupporter xenapi.HostRef
	for _, hostRef := range hostRefs {
		if hostRef != poolRecord.Master {
			hostRefSupporter = hostRef
		}
	}

	// eject the host from the pool
	taskRef, err := xenapi.Pool.AsyncEject(session, hostRefSupporter)
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
	hostRefs, err = xenapi.Host.GetAll(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if len(hostRefs) != 1 {
		t.Log("Host eject failed")
		t.Fail()
		return
	}
}
