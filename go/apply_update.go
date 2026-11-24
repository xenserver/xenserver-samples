package main

import (
	"fmt"

	"go/xenapi"
)

// applyUpdate - Apply updates from the CDN.
//
// Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator, unless
// you name another - then act on that host's post-update guidance.
//
// The documentation asks for the coordinator to be updated before any other host, so update it first,
// then run this again naming each of the others - or use rolling-pool-update to do the whole pool in
// one go. Before changing anything, checkNoPendingGuidance stops if a host or VM still has mandatory
// guidance pending from an earlier update. attachUpdateRepository checks that HA and Workload
// Balancing are off and attaches a throwaway update repository, which Pool.SyncUpdates needs; it is
// forgotten again afterwards. applyUpdatesToHost does the rest: evacuating the host first if that
// turns out to be needed, acting on its post-update guidance, and returning it to service. Finally
// report the guidance left for VMs, such as restarting one to pick the update up - that is the VM
// owner's call.
func applyUpdate(url, user, password, repoURL, sourceURL, hostName string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	var hostRef xenapi.HostRef
	if hostName != "" {
		hosts, err := xenapi.Host.GetByNameLabel(session, hostName)
		check(err)
		if len(hosts) != 1 {
			panic(fmt.Sprintf("expected one host named %q, found %d", hostName, len(hosts)))
		}
		hostRef = hosts[0]
	} else {
		hostRef, err = xenapi.Pool.GetMaster(session, pool)
		check(err)
	}
	name, err := xenapi.Host.GetNameLabel(session, hostRef)
	check(err)
	checkNoPendingGuidance(session)

	repo, previous := attachUpdateRepository(session, pool, repoURL, sourceURL)
	defer func() { detachUpdateRepository(session, pool, repo, previous) }()
	// Sync the pool's update metadata; the returned hash identifies the synced set.
	hash, err := xenapi.Pool.SyncUpdates5(session, pool, false, "", "")
	check(err)
	fmt.Printf("Synced updates; hash length %d\n", len(hash))
	session = applyUpdatesToHost(session, url, user, password, hostRef, hash, name+": ")
	reportVMGuidance(session)
	fmt.Println("OK: apply-update")
}
