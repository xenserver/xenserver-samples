package main

import (
	"fmt"

	"go/xenapi"
)

// srUsage - Storage repository usage.
//
// Report each storage repository's used and total capacity, and rescan one.
//
// Run it:
//
//	srUsage("https://xenserver", "root", password)
func srUsage(url, user, password string) {
	const GiB = 1024 * 1024 * 1024

	session := connect(url, user, password)
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var scanMe xenapi.SRRef
	haveScan := false
	for ref, sr := range srs {
		if sr.PhysicalSize <= 0 { // skip ISO/DVD pseudo-SRs
			continue
		}
		fmt.Printf("  %s: %d / %d GiB used\n", sr.NameLabel, sr.PhysicalUtilisation/GiB, sr.PhysicalSize/GiB)
		if !haveScan {
			scanMe, haveScan = ref, true
		}
	}
	// A rescan refreshes an SR's utilisation from its backend.
	if haveScan {
		check(xenapi.SR.Scan(session, scanMe))
	}

	// Read caching keeps recently-read blocks in the host's memory. It is switched off per SR by setting
	// o_direct, which asks the storage layer to bypass the cache entirely.
	if haveScan {
		check(xenapi.SR.RemoveFromOtherConfig(session, scanMe, "o_direct"))
		check(xenapi.SR.AddToOtherConfig(session, scanMe, "o_direct", "true"))
		oc, _ := xenapi.SR.GetOtherConfig(session, scanMe)
		name, _ := xenapi.SR.GetNameLabel(session, scanMe)
		readCaching := "on"
		if oc["o_direct"] == "true" {
			readCaching = "off"
		}
		fmt.Printf("  read caching on %s: %s\n", name, readCaching)
		check(xenapi.SR.RemoveFromOtherConfig(session, scanMe, "o_direct"))
	}
	fmt.Println("OK: sr-usage")
	session.Logout()
}
