package main

import (
	"encoding/json"
	"fmt"
	"sort"

	"go/xenapi"
)

// disasterRecovery - Recover VMs after a disaster.
//
// Replicate the pool's database to shared storage, read it back as a separate database to see what
// it describes, and recover a VM out of it into a second, standby pool (dr_url).
//
// Disaster recovery works by writing the pool's own database out to a storage repository as a disk
// of type "metadata". That disk can be read back as a SEPARATE database, so the ordinary calls
// describe the pool as it was replicated rather than the pool you are connected to. Recovering
// reads from that database and writes into a live pool, which is why the recover call is made on
// the metadata session and takes a live session as its destination.
//
// That destination has to be a DIFFERENT, standby pool: recovering a VM back into the exact pool
// it was replicated from can't actually succeed with force=false - the VM's uuid already exists
// there, so VM.recover always takes the replace-or-fail path, and nothing replicated a moment ago
// from a live database can ever be "newer" than the live object it came from
// (VM_TO_IMPORT_IS_NOT_NEWER_VERSION). The one-line "fix" of passing force=true instead would make
// it succeed by REPLACING (destroying and recreating) the live original - exactly the opposite of
// what a DR demo should show, and the thing that would actually destroy a live VM if ever pointed
// at the same pool it replicated from. A second pool is the only way force=false succeeds, and
// what every real DR workflow actually does. Track the recovered VM by uuid, never by name: a
// name can coincidentally collide with something already on the destination pool.
func disasterRecovery(url, user, password, drURL string) {
	if drURL == "" {
		panic("disaster-recovery needs a second pool to recover into: pass dr_url=<url of a standby pool>")
	}
	session := connect(url, user, password)
	defer session.Logout()
	drSession := connect(drURL, user, password)
	defer drSession.Logout()

	// Replication needs shared storage the standby pool can attach too, and only block storage (iSCSI,
	// HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. The server checks rather than taking
	// your word for it, so ask each candidate, as XenCenter's DR wizard does.
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var sr xenapi.SRRef
	for ref, r := range srs {
		if r.Shared && r.ContentType != "iso" && xenapi.SR.AssertSupportsDatabaseReplication(session, ref) == nil {
			sr = ref
			break
		}
	}
	if sr == "" {
		panic("no shared SR here supports database replication (it needs iSCSI or HBA storage)")
	}
	srName, _ := xenapi.SR.GetNameLabel(session, sr)
	fmt.Printf("Replicating pool metadata to %s\n", srName)
	check(xenapi.SR.EnableDatabaseReplication(session, sr))

	// Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from the pool
	// you fail over to: it has the same SR attached, rescans it to see the metadata disk just written,
	// opens the database there, and recovers into itself - VM.recover's session_to has to be a session of
	// the server running the call (HANDLE_INVALID otherwise).
	srUUID, err := xenapi.SR.GetUUID(session, sr)
	check(err)
	drSR, err := xenapi.SR.GetByUUID(drSession, srUUID)
	if err != nil {
		panic(fmt.Sprintf("the standby pool has not attached %s: attach the same storage there first", srName))
	}
	check(xenapi.SR.Scan(drSession, drSR))
	vdis, err := xenapi.SR.GetVDIs(drSession, drSR)
	check(err)
	var metadataVdi xenapi.VDIRef
	for _, v := range vdis {
		if t, _ := xenapi.VDI.GetType(drSession, v); t == xenapi.VdiTypeMetadata {
			metadataVdi = v
			break
		}
	}
	uuid, _ := xenapi.VDI.GetUUID(drSession, metadataVdi)
	fmt.Printf("  metadata disk: %s\n", uuid)

	metadataSession, err := xenapi.VDI.OpenDatabase(drSession, metadataVdi)
	check(err)

	// The Go binding keeps its session private and offers no way to build one from a session id it did
	// not create, so the metadata database has to be driven over plain JSON-RPC. Same reason the
	// destination pool's session id is obtained separately: recover() needs one to say where the VM
	// should land.
	drSessionID := rawLogin(drURL, user, password)
	var recoverable map[string]struct {
		UUID            string `json:"uuid"`
		NameLabel       string `json:"name_label"`
		IsATemplate     bool   `json:"is_a_template"`
		IsControlDomain bool   `json:"is_control_domain"`
		IsASnapshot     bool   `json:"is_a_snapshot"`
	}
	check(json.Unmarshal(rawRPC(drURL, "VM.get_all_records", string(metadataSession)), &recoverable))

	// Only real guest VMs are recoverable - exclude templates, control domains and snapshots.
	targets := make([]string, 0, len(recoverable))
	for ref, r := range recoverable {
		if !r.IsATemplate && !r.IsControlDomain && !r.IsASnapshot {
			targets = append(targets, ref)
		}
	}
	fmt.Printf("  the replicated database describes %d recoverable VM(s)\n", len(targets))

	sort.Slice(targets, func(i, j int) bool {
		return recoverable[targets[i]].NameLabel < recoverable[targets[j]].NameLabel
	})
	// Only a VM whose disks are all on storage the standby pool can see can be recovered there - the
	// check runs on the METADATA session, and session_to says where the VM should land: the STANDBY
	// pool's session, not this one. Take the first (by name) that passes, as the DR wizard lists them.
	target := ""
	for _, t := range targets {
		if _, failure := rawRPCCall(drURL, "VM.assert_can_be_recovered", string(metadataSession), t, drSessionID); failure == nil {
			target = t
			break
		}
	}
	if target == "" {
		panic("no VM in the replicated database has all its disks on storage the standby pool can see")
	}
	targetUUID := recoverable[target].UUID
	name := recoverable[target].NameLabel
	fmt.Printf("  recovering %s\n", name)

	// Never force=true: see the doc comment above.
	rawRPC(drURL, "VM.recover", string(metadataSession), target, drSessionID, false)

	// It is a real VM on the standby pool now, not merely a call that returned - look it up by the
	// uuid full_restore preserved, never by name.
	recovered, err := xenapi.VM.GetByUUID(drSession, targetUUID)
	check(err)
	ps, _ := xenapi.VM.GetPowerState(drSession, recovered)
	fmt.Printf("  %s is %s on the standby pool\n", name, ps)

	// Tidy up on the standby pool only, by uuid - never touch the source pool's VMs, and never guess
	// by name (a coincidentally-same-named VM must not be destroyed). Destroy the VM record but NOT its
	// disks: they are the protected pool's own disks on the shared SR, not copies.
	check(xenapi.VM.Destroy(drSession, recovered))

	check(xenapi.SR.DisableDatabaseReplication(session, sr))
	fmt.Println("OK: disaster-recovery")
}
