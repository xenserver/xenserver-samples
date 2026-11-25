package main

import (
	"fmt"

	"go/xenapi"
)

// rollingPoolUpdate - Rolling pool update.
//
// Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
// coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
// update asks for that, and return it to service.
//
// Check first, before changing anything, that the update can go through: no host or VM may still
// have mandatory guidance pending from an earlier update, and every host must be able to empty
// (checkNoPendingGuidance, checkHostsCanBeEvacuated). Then sync, and let updateHosts update each host
// in turn: disable it, evacuate it, apply the updates, restart it or its toolstack if the update asks
// for that, and enable it again. Finally report the guidance left for VMs, such as restarting one to
// pick the update up - that is the VM owner's call. attachUpdateRepository checks that HA and
// Workload Balancing are off and attaches a throwaway update repository, which Pool.SyncUpdates
// needs; it is forgotten again afterwards.
func rollingPoolUpdate(url, user, password, repoURL, sourceURL string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	hosts := hostsCoordinatorFirst(session)
	checkNoPendingGuidance(session)
	checkHostsCanBeEvacuated(session, hosts)

	repo, previous := attachUpdateRepository(session, pool, repoURL, sourceURL)
	defer func() { detachUpdateRepository(session, pool, repo, previous) }()
	hash, err := xenapi.Pool.SyncUpdates5(session, pool, false, "", "")
	check(err)
	fmt.Printf("Synced updates; hash length %d\n", len(hash))
	session = updateHosts(session, url, user, password, hosts, hash)
	reportVMGuidance(session)
	fmt.Println("OK: rolling-pool-update")
}
