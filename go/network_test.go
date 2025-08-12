package testGoSDK

import (
	"fmt"
	"testing"
	"time"

	"xenapi"
)

func TestNetworkCreateAndDestroy(t *testing.T) {
	if stopTests {
		t.Skip("Skipping due to login failure")
	}

	var networkRecord xenapi.NetworkRecord
	networkRecord.NameLabel = "Test External Network"
	networkRecord.NameDescription = fmt.Sprintf("Created by network_test.go at %s", time.Now().String())
	networkRecord.Managed = true

	t.Log("Adding new network:", networkRecord.NameLabel)
	networkRef, err := xenapi.Network.Create(session, networkRecord)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	networkRecord, err = xenapi.Network.GetRecord(session, networkRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	// Select the first Nic and create a VLAN
	pifRecords, err := xenapi.PIF.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	var selectPifRef xenapi.PIFRef
	for pifRef, pifRecord := range pifRecords {
		if pifRecord.Physical && pifRecord.BondSlaveOf == "OpaqueRef:NULL" {
			selectPifRef = pifRef
			break
		}
	}
	_, err = xenapi.Pool.CreateVLANFromPIF(session, selectPifRef, networkRef, 100)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	pifRefs, err := xenapi.Network.GetPIFs(session, networkRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	pifRecord, err := xenapi.PIF.GetRecord(session, pifRefs[0])
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	vlanRecord, err := xenapi.VLAN.GetRecord(session, pifRecord.VLANMasterOf)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if vlanRecord.Tag != 100 {
		t.Log("Could not match VLAN tag.")
		t.Fail()
		return
	}
	vifRefs, err := xenapi.Network.GetVIFs(session, networkRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if len(vifRefs) != 0 {
		t.Log("Should not have any VIFs on this network.")
		t.Fail()
		return
	}

	// Change the network MTU
	err = xenapi.Network.SetMTU(session, networkRef, 1600)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	mtu, err := xenapi.Network.GetMTU(session, networkRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if mtu != 1600 {
		t.Log("MTU is not set correctly.")
		t.Fail()
		return
	}

	for _, pifRef := range pifRefs {
		pifRecord, err := xenapi.PIF.GetRecord(session, pifRef)
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
		err = xenapi.VLAN.Destroy(session, pifRecord.VLANMasterOf)
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
	}
	err = xenapi.Network.Destroy(session, networkRef)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
}
