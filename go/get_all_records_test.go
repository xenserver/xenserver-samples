package testGoSDK

import (
	"testing"

	xenapi "github.com/xenserver/xenserver-samples/go/goSDK"
)

func TestGetAllRecords(t *testing.T) {
	// Get all records
	_, err := xenapi.Blob.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Bond.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Certificate.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.ClusterHost.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Cluster.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Console.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Crashdump.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.DRTask.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Feature.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.GPUGroup.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.HostCPU.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.HostCrashdump.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.HostMetrics.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.HostPatch.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Host.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Message.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.NetworkSriov.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Network.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PIFMetrics.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if session.APIVersion >= xenapi.APIVersion2_21 {
		_, err = xenapi.Observer.GetAllRecords(session)
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
	}
	_, err = xenapi.PBD.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PCI.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PGPU.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PIFMetrics.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PIF.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PoolPatch.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PoolUpdate.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Pool.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PUSB.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PVSCacheStorage.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PVSProxy.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PVSServer.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.PVSSite.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if session.APIVersion >= xenapi.APIVersion2_21 {
		_, err = xenapi.Repository.GetAllRecords(session)
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
	}
	_, err = xenapi.Role.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.SDNController.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Secret.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.SM.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.SR.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Subject.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Task.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.Tunnel.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.USBGroup.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	// XAPI Message Removed
	// _, err = xenapi.VBDMetrics.GetAllRecords(session)
	// if err != nil {
	// 	t.Log(err)
	// 	t.Fail()
	// 	return
	// }
	_, err = xenapi.VBD.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.VDI.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.VGPUType.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.VGPU.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	// XAPI Message Removed
	// _, err = xenapi.VIFMetrics.GetAllRecords(session)
	// if err != nil {
	// 	t.Log(err)
	// 	t.Fail()
	// 	return
	// }
	_, err = xenapi.VIF.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.VLAN.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.VMAppliance.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.VMGuestMetrics.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.VMMetrics.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	_, err = xenapi.VM.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	// XAPI Message Removed
	// _, err = xenapi.VMPP.GetAllRecords(session)
	// if err != nil {
	// 	t.Log(err)
	// 	t.Fail()
	// 	return
	// }
	_, err = xenapi.VMSS.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	if session.APIVersion >= xenapi.APIVersion2_21 {
		_, err = xenapi.VTPM.GetAllRecords(session)
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
	}
	_, err = xenapi.VUSB.GetAllRecords(session)
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
}
