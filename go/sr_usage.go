package main

import (
	"fmt"
	"sort"
	"strings"

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

	type namedSR struct {
		ref xenapi.SRRef
		rec xenapi.SRRecord
	}
	ordered := make([]namedSR, 0, len(srs))
	for ref, sr := range srs {
		ordered = append(ordered, namedSR{ref, sr})
	}
	sort.Slice(ordered, func(i, j int) bool {
		return strings.ToLower(ordered[i].rec.NameLabel) < strings.ToLower(ordered[j].rec.NameLabel)
	})

	var scanMe xenapi.SRRef
	haveScan := false
	for _, sr := range ordered {
		if sr.rec.PhysicalSize <= 0 { // skip ISO/DVD pseudo-SRs
			continue
		}
		fmt.Printf("  %s: %d / %d GiB used\n", sr.rec.NameLabel, sr.rec.PhysicalUtilisation/GiB, sr.rec.PhysicalSize/GiB)
		if !haveScan {
			scanMe, haveScan = sr.ref, true
		}
	}
	// A rescan refreshes an SR's utilisation from its backend.
	if haveScan {
		check(xenapi.SR.Scan(session, scanMe))
	}
	fmt.Println("OK: sr-usage")
	session.Logout()
}
