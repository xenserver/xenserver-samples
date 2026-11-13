package main

import (
	"fmt"

	"go/xenapi"
)

// manageCrashDumps - Clear a host's crash dumps.
//
// Find the crash dumps a host kept after a failure, report how big and how old they are, then
// delete them to free the space.
func manageCrashDumps(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	// When a host crashes it writes a dump to its local disk and keeps it. They are large, nothing cleans
	// them up, and a host that has crashed more than once accumulates them - so clearing them once support
	// has what it needs is ordinary housekeeping. They belong to the host that wrote them, so clear them a
	// host at a time.
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	var host xenapi.HostRef
	var dumps []xenapi.HostCrashdumpRef
	for _, h := range hosts {
		d, err := xenapi.Host.GetCrashdumps(session, h)
		check(err)
		if len(d) > 0 {
			host, dumps = h, d
			break
		}
	}
	if len(dumps) == 0 {
		fmt.Println("No crash dumps in this pool - nothing to clear.")
		fmt.Println("OK: manage-crash-dumps")
		return
	}

	name, _ := xenapi.Host.GetNameLabel(session, host)
	fmt.Printf("%s has %d crash dump(s)\n", name, len(dumps))
	var total int64
	for _, dump := range dumps {
		record, err := xenapi.HostCrashdump.GetRecord(session, dump)
		check(err)
		total += record.Size
		fmt.Printf("  %s  %s\n", record.Timestamp.Format("20060102T15:04:05Z"), mib(record.Size))
	}
	fmt.Printf("  %s in total\n", mib(total))

	// Deleting a dump frees the space on the host; the host itself is untouched.
	for _, dump := range dumps {
		check(xenapi.HostCrashdump.Destroy(session, dump))
	}
	left, _ := xenapi.Host.GetCrashdumps(session, host)
	fmt.Printf("  cleared:  %s now has %d\n", name, len(left))

	fmt.Println("OK: manage-crash-dumps")
}

func mib(size int64) string { return fmt.Sprintf("%d MiB", size/(1024*1024)) }
