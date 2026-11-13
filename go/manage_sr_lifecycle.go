package main

import (
	"fmt"

	"go/xenapi"
)

// manageSrLifecycle - Detach, reattach and forget storage.
//
// Take a storage repository offline and bring it back: disconnect it from every host, reconnect and
// rescan it, then disconnect it once more and forget it for good.
func manageSrLifecycle(url, user, password, nfsServer, nfsPath string) {
	session := connect(url, user, password)
	defer session.Logout()

	// There is no "detach" call on an SR. A shared SR is joined to each host by one PBD - a physical
	// block device - and detaching the SR means unplugging every one of them. That is why an SR can be
	// attached on some hosts and not others, and why a repair action exists at all: it plugs back the
	// PBDs that are missing.
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	sr, err := xenapi.SR.Create(session, hosts[0], map[string]string{
		"server":     nfsServer,
		"serverpath": nfsPath,
		"nfsversion": "3",
	}, 0, "sdk-example-lifecycle", "SR used by the SDK lifecycle example",
		"nfs", "user", true, map[string]string{})
	check(err)

	pbds, err := xenapi.SR.GetPBDs(session, sr)
	check(err)
	name, _ := xenapi.SR.GetNameLabel(session, sr)
	fmt.Printf("%s: connected on %d of %d host(s)\n", name, attachedPbds(session, pbds), len(pbds))

	for _, pbd := range pbds {
		check(xenapi.PBD.Unplug(session, pbd))
	}
	fmt.Printf("  detached:   connected on %d host(s)\n", attachedPbds(session, pbds))

	// Plugging them back is exactly what a repair does.
	for _, pbd := range pbds {
		check(xenapi.PBD.Plug(session, pbd))
	}
	fmt.Printf("  reattached: connected on %d host(s)\n", attachedPbds(session, pbds))

	check(xenapi.SR.Scan(session, sr))
	vdis, err := xenapi.SR.GetVDIs(session, sr)
	check(err)
	fmt.Printf("  rescanned:  %d disk(s)\n", len(vdis))

	// Forgetting drops the pool's record of the SR but leaves the storage itself untouched, so the same
	// export can be introduced again later. Detach before forgetting: a connected SR is still in use.
	for _, pbd := range pbds {
		check(xenapi.PBD.Unplug(session, pbd))
	}
	check(xenapi.SR.Forget(session, sr))
	fmt.Println("  forgotten")
	fmt.Println("OK: manage-sr-lifecycle")
}

// attachedPbds reports how many of these connections are currently live.
func attachedPbds(session *xenapi.Session, pbds []xenapi.PBDRef) int {
	live := 0
	for _, pbd := range pbds {
		attached, err := xenapi.PBD.GetCurrentlyAttached(session, pbd)
		check(err)
		if attached {
			live++
		}
	}
	return live
}
