package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// reclaimSpace - Reclaim freed space on a thin SR.
//
// Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a
// trim-capable SR, pick a host with a live connection to it, and run the trim operation.
func reclaimSpace(url, user, password string) {
	const GiB = 1024 * 1024 * 1024

	session := connect(url, user, password)

	// Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
	sms, err := xenapi.SM.GetAllRecords(session)
	check(err)
	trimTypes := map[string]bool{}
	for _, sm := range sms {
		if _, ok := sm.Features["SR_TRIM"]; ok {
			trimTypes[sm.Type] = true
		}
	}

	// SR.GetAll keeps the server's order (GetAllRecords returns a map, which Go ranges in random order),
	// so this takes the same SR as the other languages.
	srRefs, err := xenapi.SR.GetAll(session)
	check(err)
	var srRef xenapi.SRRef
	var sr xenapi.SRRecord
	found := false
	for _, ref := range srRefs {
		r, err := xenapi.SR.GetRecord(session, ref)
		check(err)
		if r.PhysicalSize > 0 && trimTypes[r.Type] {
			srRef, sr, found = ref, r, true
			break
		}
	}
	if !found {
		panic("no trim-capable SR found")
	}

	// A host with a currently-attached PBD can reach the SR to run the plugin.
	var host xenapi.HostRef
	for _, pbdRef := range sr.PBDs {
		pbd, err := xenapi.PBD.GetRecord(session, pbdRef)
		check(err)
		if pbd.CurrentlyAttached {
			host = pbd.Host
			break
		}
	}

	fmt.Printf("  %s: %d / %d GiB used\n", sr.NameLabel, sr.PhysicalUtilisation/GiB, sr.PhysicalSize/GiB)

	result, err := xenapi.Host.CallPlugin(session, host, "trim", "do_trim",
		map[string]string{"sr_uuid": sr.UUID})
	check(err)
	fmt.Printf("  reclaimed freed space on %s: %s\n", sr.NameLabel, result)
	// Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
	if strings.ToLower(strings.TrimSpace(result)) != "true" {
		panic("trim plugin returned " + result)
	}

	// Rescan to refresh utilisation from the backend, the same way srUsage does, before reporting it.
	check(xenapi.SR.Scan(session, srRef))
	usedAfter, err := xenapi.SR.GetPhysicalUtilisation(session, srRef)
	check(err)
	fmt.Printf("  %s: %d / %d GiB used\n", sr.NameLabel, usedAfter/GiB, sr.PhysicalSize/GiB)
	fmt.Println("OK: reclaim-space")
	session.Logout()
}
