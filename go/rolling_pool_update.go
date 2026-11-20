package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// rollingPoolUpdate - Rolling pool update.
//
// Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
// coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
// update asks for that, and return it to service.
//
// Check first that every host can be emptied: Host.GetVmsWhichPreventEvacuation names the VMs that
// could not move anywhere else (for example a VM with a disk on the host's local storage, or a pool
// with nowhere else to put them) - stop before changing anything if there are any. Then, for each
// host: disable it so nothing new starts there, evacuate it (live-migrating its VMs to the other
// hosts), and let applyUpdatesToHost apply the updates, restart the host or its toolstack if the
// update asks for that, and enable it again. The VMs stay where evacuation put them.
// attachUpdateRepository checks that HA and Workload Balancing are off and attaches a throwaway update
// repository, which Pool.SyncUpdates needs; it is forgotten again afterwards.
func rollingPoolUpdate(url, user, password, repoURL, sourceURL string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	master, err := xenapi.Pool.GetMaster(session, pool)
	check(err)
	all, err := xenapi.Host.GetAll(session)
	check(err)
	hosts := []xenapi.HostRef{master}
	for _, hostRef := range all {
		if hostRef != master {
			hosts = append(hosts, hostRef)
		}
	}
	for _, hostRef := range hosts {
		blocking, err := xenapi.Host.GetVmsWhichPreventEvacuation(session, hostRef)
		check(err)
		if len(blocking) > 0 {
			var names []string
			for vm := range blocking {
				name, err := xenapi.VM.GetNameLabel(session, vm)
				check(err)
				names = append(names, name)
			}
			hostName, err := xenapi.Host.GetNameLabel(session, hostRef)
			check(err)
			panic(fmt.Sprintf("%s cannot be evacuated: move or shut down %s first", hostName,
				strings.Join(names, ", ")))
		}
	}

	repo, previous := attachUpdateRepository(session, pool, repoURL, sourceURL)
	defer func() { detachUpdateRepository(session, pool, repo, previous) }()
	hash, err := xenapi.Pool.SyncUpdates5(session, pool, false, "", "")
	check(err)
	fmt.Printf("Synced updates; hash length %d\n", len(hash))
	for _, hostRef := range hosts {
		name, err := xenapi.Host.GetNameLabel(session, hostRef)
		check(err)
		fmt.Printf("Updating %s: moving its VMs to the rest of the pool\n", name)
		check(xenapi.Host.Disable(session, hostRef, true))
		check(xenapi.Host.Evacuate2(session, hostRef))
		session = applyUpdatesToHost(session, url, user, password, hostRef, hash, "")
	}
	fmt.Println("OK: rolling-pool-update")
}
