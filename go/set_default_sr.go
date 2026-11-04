package main

import (
	"fmt"

	"go/xenapi"
)

// setDefaultSr - Set the pool's default storage.
//
// Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by
// default, then put the original choice back.
func setDefaultSr(url, user, password, nfsServer, nfsPath string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]

	// Capture all three separately. New disks land on the default SR, a suspended VM's memory image goes
	// to the suspend-image SR and host crash dumps to the crash-dump SR. They are usually the same
	// storage but need not be, and a pool that has never suspended or crashed anything can legitimately
	// leave the latter two unset - so restoring all three from the default would quietly invent settings
	// that were not there.
	before, err := xenapi.Pool.GetDefaultSR(session, pool)
	check(err)
	beforeSuspend, err := xenapi.Pool.GetSuspendImageSR(session, pool)
	check(err)
	beforeCrash, err := xenapi.Pool.GetCrashDumpSR(session, pool)
	check(err)
	fmt.Printf("default storage:  %s\n", srLabel(session, before))
	fmt.Printf("  suspend images: %s\n", srLabel(session, beforeSuspend))
	fmt.Printf("  crash dumps:    %s\n", srLabel(session, beforeCrash))

	// Somewhere to switch to. A pool default has to be reachable from every host, so it is a shared SR;
	// a local one would strand any VM whose disk landed on the wrong host.
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	sr, err := xenapi.SR.Create(session, hosts[0], map[string]string{
		"server":     nfsServer,
		"serverpath": nfsPath,
		"nfsversion": "3",
	}, 0, "sdk-example-default", "SR used by the SDK default-storage example",
		"nfs", "user", true, map[string]string{})
	check(err)

	check(xenapi.Pool.SetDefaultSR(session, pool, sr))
	check(xenapi.Pool.SetSuspendImageSR(session, pool, sr))
	check(xenapi.Pool.SetCrashDumpSR(session, pool, sr))
	now, _ := xenapi.Pool.GetDefaultSR(session, pool)
	fmt.Printf("  switched to:    %s\n", srLabel(session, now))

	// Restore the original choice before tidying up: an SR that is still the pool default is the awkward
	// one to remove.
	check(xenapi.Pool.SetDefaultSR(session, pool, before))
	check(xenapi.Pool.SetSuspendImageSR(session, pool, beforeSuspend))
	check(xenapi.Pool.SetCrashDumpSR(session, pool, beforeCrash))
	pbds, err := xenapi.SR.GetPBDs(session, sr)
	check(err)
	for _, pbd := range pbds {
		check(xenapi.PBD.Unplug(session, pbd))
	}
	check(xenapi.SR.Forget(session, sr))
	restored, _ := xenapi.Pool.GetDefaultSR(session, pool)
	fmt.Printf("  restored to:    %s\n", srLabel(session, restored))
	fmt.Println("OK: set-default-sr")
}
