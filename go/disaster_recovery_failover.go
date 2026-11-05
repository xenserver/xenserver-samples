package main

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"sort"
	"strings"

	"go/xenapi"
)

// disasterRecoveryFailover - Fail over to the disaster recovery site.
//
// On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's
// storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes. By
// default this is a test failover, which removes what it recovered and detaches the storage again.
//
// The replica is the LUN the storage array mirrors the protected pool's SR to: name it by the iSCSI
// target, IQN and SCSI id (srType "lvmoiscsi"), or by SCSI id alone for Fibre Channel/SAS (srType
// "lvmohba"). Before a real failover, break the mirror so that this site can write to the replica, and
// make sure no other pool has those LUNs attached: two pools using the same LUN corrupt it.
//
// DR_task.create attaches every SR on the LUN that you name (by uuid) to this pool, keeping its uuid, and
// VDI.open_database gives a session onto the metadata replicated there - a separate, read-only database,
// not this pool. Recovering runs on that session and names this pool's session as the place to recover
// into. A test failover then removes the recovered VMs and vApps - not their disks, which are the
// replica's - and detaches and forgets the SRs, as the wizard does.
//
// Run it:
//
//	disasterRecoveryFailover("https://dr-site-pool", "root", password, "192.0.2.31",
//		"iqn.2009-01.com.example:replica-0", "360a98...", "", "lvmoiscsi", true)
func disasterRecoveryFailover(url, user, password, target, targetIQN, scsiID, port, srType string, testFailover bool) {
	session := connect(url, user, password)
	defer session.Logout()

	deviceConfig := map[string]string{"SCSIid": scsiID}
	if srType == "lvmoiscsi" {
		deviceConfig["target"] = target
		deviceConfig["targetIQN"] = targetIQN
		if port != "" {
			deviceConfig["port"] = port
		}
	}

	// Which SRs are on the LUN, and which of them hold pool metadata. sm_config metadata=true asks for
	// their names and the pool_metadata_detected flag as well as their uuids.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	master, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	probe, err := xenapi.SR.Probe(session, master, deviceConfig, srType, map[string]string{"metadata": "true"})
	check(err)
	var found struct {
		SRs []struct {
			UUID         string `xml:"UUID"`
			NameLabel    string `xml:"name_label"`
			PoolMetadata string `xml:"pool_metadata_detected"`
		} `xml:"SR"`
	}
	check(xml.Unmarshal([]byte(probe), &found))
	var uuids []string
	for _, sr := range found.SRs {
		uuid := strings.TrimSpace(sr.UUID)
		withMetadata := ""
		if strings.TrimSpace(sr.PoolMetadata) == "true" {
			withMetadata = ", with pool metadata"
		}
		fmt.Printf("Found SR %s (%s)%s\n", strings.TrimSpace(sr.NameLabel), uuid, withMetadata)
		uuids = append(uuids, uuid)
	}
	if len(uuids) == 0 {
		panic("there is no SR on that LUN")
	}

	task, err := xenapi.DRTask.Create(session, srType, deviceConfig, uuids)
	check(err)
	introduced, err := xenapi.DRTask.GetIntroducedSRs(session, task)
	check(err)
	var attached []string
	for _, sr := range introduced {
		name, err := xenapi.SR.GetNameLabel(session, sr)
		check(err)
		attached = append(attached, name)
	}
	fmt.Printf("Attached %s\n", strings.Join(attached, ", "))

	// The Go binding cannot make calls on a session it did not log in itself, so the calls on the
	// replicated database go over plain JSON-RPC (see rawRPCCall). For the same reason it cannot hand over
	// its own session id, so session_to - this pool, where the VMs are to land - is a second login here.
	sessionTo := rawLogin(url, user, password)
	defer rawRPCCall(url, "session.logout", sessionTo)

	// Recover from every replicated database on the attached SRs: vApps first (their VMs come with them),
	// then the VMs not in a vApp. A VM whose disks are on storage this pool hasn't attached can't be
	// recovered - assert_can_be_recovered says so (VM_REQUIRES_SR) - so skip it.
	var recoveredVMs, recoveredVApps []string
	for _, sr := range introduced {
		vdis, err := xenapi.SR.GetVDIs(session, sr)
		check(err)
		for _, vdi := range vdis {
			t, err := xenapi.VDI.GetType(session, vdi)
			check(err)
			latest, err := xenapi.VDI.GetMetadataLatest(session, vdi)
			check(err)
			if t != xenapi.VdiTypeMetadata || !latest {
				continue
			}
			ref, err := xenapi.VDI.OpenDatabase(session, vdi)
			check(err)
			database := string(ref)

			// A pool often has no name of its own; show its coordinator's name instead.
			var poolRecords map[string]struct {
				NameLabel string `json:"name_label"`
				Master    string `json:"master"`
			}
			check(json.Unmarshal(rawRPC(url, "pool.get_all_records", database), &poolRecords))
			for _, pool := range poolRecords {
				name := pool.NameLabel
				if name == "" {
					check(json.Unmarshal(rawRPC(url, "host.get_name_label", database, pool.Master), &name))
				}
				fmt.Printf("  pool metadata of %s\n", name)
			}

			inRecoveredVApp := map[string]bool{}
			var vapps map[string]struct {
				UUID      string   `json:"uuid"`
				NameLabel string   `json:"name_label"`
				VMs       []string `json:"VMs"`
			}
			check(json.Unmarshal(rawRPC(url, "VM_appliance.get_all_records", database), &vapps))
			for vapp, r := range vapps {
				if _, failure := rawRPCCall(url, "VM_appliance.assert_can_be_recovered", database, vapp, sessionTo); failure != nil {
					fmt.Printf("  cannot recover vApp %s: %s\n", r.NameLabel, rawFailureCode(failure))
					continue
				}
				rawRPC(url, "VM_appliance.recover", database, vapp, sessionTo, false)
				recoveredVApps = append(recoveredVApps, r.UUID)
				for _, vm := range r.VMs {
					var uuid string
					check(json.Unmarshal(rawRPC(url, "VM.get_uuid", database, vm), &uuid))
					recoveredVMs = append(recoveredVMs, uuid)
					inRecoveredVApp[vm] = true
				}
				fmt.Printf("  recovered vApp %s\n", r.NameLabel)
			}

			var vms map[string]struct {
				UUID            string `json:"uuid"`
				NameLabel       string `json:"name_label"`
				IsATemplate     bool   `json:"is_a_template"`
				IsControlDomain bool   `json:"is_control_domain"`
				IsASnapshot     bool   `json:"is_a_snapshot"`
			}
			check(json.Unmarshal(rawRPC(url, "VM.get_all_records", database), &vms))
			refs := make([]string, 0, len(vms))
			for vm := range vms {
				refs = append(refs, vm)
			}
			sort.Slice(refs, func(i, j int) bool { return vms[refs[i]].NameLabel < vms[refs[j]].NameLabel })
			for _, vm := range refs {
				r := vms[vm]
				if r.IsATemplate || r.IsControlDomain || r.IsASnapshot || inRecoveredVApp[vm] {
					continue
				}
				if _, failure := rawRPCCall(url, "VM.assert_can_be_recovered", database, vm, sessionTo); failure != nil {
					fmt.Printf("  cannot recover %s: %s\n", r.NameLabel, rawFailureCode(failure))
					continue
				}
				rawRPC(url, "VM.recover", database, vm, sessionTo, false)
				recoveredVMs = append(recoveredVMs, r.UUID)
				fmt.Printf("  recovered %s\n", r.NameLabel)
			}
			rawRPC(url, "session.logout", database)
		}
	}

	// The recovered VMs keep their uuids, so look them up by uuid - a name may be taken here already.
	for _, uuid := range recoveredVMs {
		vm, err := xenapi.VM.GetByUUID(session, uuid)
		check(err)
		name, err := xenapi.VM.GetNameLabel(session, vm)
		check(err)
		state, err := xenapi.VM.GetPowerState(session, vm)
		check(err)
		fmt.Printf("%s is %s\n", name, state)
	}

	if testFailover {
		for _, uuid := range recoveredVMs {
			vm, err := xenapi.VM.GetByUUID(session, uuid)
			check(err)
			if state, err := xenapi.VM.GetPowerState(session, vm); err == nil && state != xenapi.VMPowerStateHalted {
				check(xenapi.VM.HardShutdown(session, vm))
			}
			check(xenapi.VM.Destroy(session, vm))
		}
		for _, uuid := range recoveredVApps {
			vapp, err := xenapi.VMAppliance.GetByUUID(session, uuid)
			check(err)
			check(xenapi.VMAppliance.Destroy(session, vapp))
		}
	}
	// Destroying the task detaches and forgets the SRs it attached that no recovered VM needs.
	check(xenapi.DRTask.Destroy(session, task))
	if testFailover {
		// The SRs the recovered VMs needed are no longer the task's: detach and forget those too.
		for _, sr := range introduced {
			pbds, err := xenapi.SR.GetPBDs(session, sr)
			if err != nil && failureCode(err) == xenapi.ErrorHandleInvalid {
				continue // forgotten by DR_task.destroy
			}
			check(err)
			for _, pbd := range pbds {
				if attached, err := xenapi.PBD.GetCurrentlyAttached(session, pbd); err == nil && attached {
					check(xenapi.PBD.Unplug(session, pbd))
				}
			}
			check(xenapi.SR.Forget(session, sr))
		}
		fmt.Println("Test failover: removed the recovered VMs and detached the replica")
	} else {
		fmt.Println("Recovered VMs are halted: start them when you are ready")
	}
	fmt.Println("OK: disaster-recovery-failover")
}

// rawFailureCode is the XenAPI error code in a JSON-RPC error (its message).
func rawFailureCode(failure json.RawMessage) string {
	var e struct {
		Message string `json:"message"`
	}
	if json.Unmarshal(failure, &e) == nil && e.Message != "" {
		return e.Message
	}
	return string(failure)
}
