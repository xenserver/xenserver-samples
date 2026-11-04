package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// configureDisasterRecovery - Configure disaster recovery.
//
// Turn on pool metadata replication: the pool writes its database - the configuration of its VMs and
// vApps - to a disk on an iSCSI or Fibre Channel SR, as XenCenter's Configure DR dialog does. Have your
// storage array replicate that SR, and the VMs' SRs, to the disaster recovery site; a pool there can then
// recover the VMs from the replica (see disasterRecoveryFailover).
//
// Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every host
// must have the SR attached. The server says which qualify: SR.assert_supports_database_replication fails
// for any that can't (an NFS SR fails SR_OPERATION_NOT_SUPPORTED), so ask each one rather than guessing
// from its type, as the Configure DR dialog does. A pool can replicate to up to 8 SRs.
//
// Replication is only useful while it is on. So that the example leaves the pool as it found it, it
// turns replication off again if it was off to start with; in practice, leave it on.
//
// Run it:
//
//	configureDisasterRecovery("https://xenserver", "root", password, "")
func configureDisasterRecovery(url, user, password, srName string) {
	session := connect(url, user, password)
	defer session.Logout()

	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var candidates []xenapi.SRRef
	var names []string
	for ref, r := range srs {
		if r.Shared && r.ContentType != "iso" && xenapi.SR.AssertSupportsDatabaseReplication(session, ref) == nil {
			candidates = append(candidates, ref)
			names = append(names, r.NameLabel)
		}
	}
	if len(names) == 0 {
		names = []string{"none"}
	}
	fmt.Printf("SRs that can hold the pool metadata: %s\n", strings.Join(names, ", "))
	if srName != "" {
		var named []xenapi.SRRef
		for _, sr := range candidates {
			if srs[sr].NameLabel == srName {
				named = append(named, sr)
			}
		}
		candidates = named
	}
	if len(candidates) == 0 {
		what := ""
		if srName != "" {
			what = fmt.Sprintf(" named %q", srName)
		}
		panic(fmt.Sprintf("no SR here can hold the pool metadata%s: it needs an iSCSI or Fibre Channel "+
			"SR attached to every host", what))
	}
	sr := candidates[0]
	name := srs[sr].NameLabel

	// The pool's own metadata disk on this SR is what says replication is on (as the Configure DR dialog
	// decides): a disk of type metadata whose metadata_of_pool is this pool.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	metadataDisk := func() xenapi.VDIRef {
		vdis, err := xenapi.SR.GetVDIs(session, sr)
		check(err)
		for _, v := range vdis {
			t, err := xenapi.VDI.GetType(session, v)
			check(err)
			of, err := xenapi.VDI.GetMetadataOfPool(session, v)
			check(err)
			if t == xenapi.VdiTypeMetadata && of == pools[0] {
				return v
			}
		}
		return ""
	}

	wasOn := metadataDisk() != ""
	if wasOn {
		fmt.Printf("The pool metadata is already replicated to %s\n", name)
	} else {
		fmt.Printf("Replicating the pool metadata to %s\n", name)
		check(xenapi.SR.EnableDatabaseReplication(session, sr))
	}

	vdi, err := xenapi.VDI.GetRecord(session, metadataDisk())
	check(err)
	fmt.Printf("  metadata disk: %s (%s), %d MiB, up to date: %t\n",
		vdi.NameLabel, vdi.UUID, vdi.VirtualSize/(1024*1024), vdi.MetadataLatest)

	if !wasOn {
		// Turning replication off destroys the metadata disk.
		check(xenapi.SR.DisableDatabaseReplication(session, sr))
		fmt.Println("Turned replication off again, as it was before")
	}
	fmt.Println("OK: configure-disaster-recovery")
}
