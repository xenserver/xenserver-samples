package main

import (
	"fmt"

	"go/xenapi"
)

// rollingPoolUpdate applies the CDN's updates host-by-host, coordinator first, so the pool never
// goes fully offline.
//
// Host.ApplyUpdates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
// Workload Balancing to be switched off before you start updating - so check both up front and stop
// rather than disabling either for you; turn them back on again once the update is done.
//
// Needs an enabled update repository the same way apply-update does - introduce and attach a
// throwaway one, forget it again afterwards. Modern xapi (>=23.18.0) doesn't reboot a host for you:
// it only records pending_guidances, so only reboot (or restart the toolstack) when the applied
// batch actually asks for it, and only evacuate a host first if applying without doing so fails
// with HOST_EVACUATION_IS_REQUIRED - most updates don't need it. Guidance that targets VMs instead
// of hosts (for example restarting a VM) is not handled here.
func rollingPoolUpdate(url, user, password, repoURL, sourceURL string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	haEnabled, err := xenapi.Pool.GetHaEnabled(session, pool)
	check(err)
	wlbEnabled, err := xenapi.Pool.GetWlbEnabled(session, pool)
	check(err)
	if haEnabled || wlbEnabled {
		panic("HA and Workload Balancing must both be off before updating the pool; disable them, " +
			"run this again, then re-enable them once it finishes")
	}
	repos := introduceUpdateRepositories(session, repoURL, sourceURL)
	// Remember the pool's own repositories, to put them back afterwards.
	previous, perr := xenapi.Pool.GetRepositories(session, pool)
	check(perr)
	check(xenapi.Pool.SetRepositories(session, pool, repos))
	defer func() {
		check(xenapi.Pool.SetRepositories(session, pool, previous))
		for _, repo := range repos {
			check(xenapi.Repository.Forget(session, repo))
		}
	}()

	hash, err := xenapi.Pool.SyncUpdates5(session, pool, false, "", "")
	check(err)
	fmt.Printf("Synced updates; hash length %d\n", len(hash))

	// The rolling pattern: apply -> evacuate and retry only if that turns out to be needed ->
	// reboot (only if asked) -> re-enable, one host at a time, coordinator first.
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	master, err := xenapi.Pool.GetMaster(session, pool)
	check(err)
	orderedRefs := []xenapi.HostRef{master}
	for hostRef := range hosts {
		if hostRef != master {
			orderedRefs = append(orderedRefs, hostRef)
		}
	}
	for _, hostRef := range orderedRefs {
		host := hosts[hostRef]
		fmt.Printf("Updating %s:\n", host.NameLabel)
		if _, err := xenapi.Host.ApplyUpdates(session, hostRef, hash); err != nil {
			if failureCode(err) != xenapi.ErrorHostEvacuationIsRequired {
				panic(err)
			}
			fmt.Println("  needs evacuating first; evacuating and retrying")
			check(xenapi.Host.Disable(session, hostRef, true)) // stop new VMs landing here
			check(xenapi.Host.Evacuate2(session, hostRef))     // move running guests to the rest of the pool
			_, err := xenapi.Host.ApplyUpdates(session, hostRef, hash)
			check(err)
			check(xenapi.Host.Enable(session, hostRef))
		}
		guidance, _ := xenapi.Host.GetPendingGuidances(session, hostRef)
		fmt.Printf("  applied; pending guidance = %v\n", guidance)
		rebootHost := containsGuidance(guidance, xenapi.UpdateGuidancesRebootHost)
		restartToolstack := containsGuidance(guidance, xenapi.UpdateGuidancesRestartToolstack)
		if rebootHost || restartToolstack {
			// Either restart returns before it has happened, and if this host is the coordinator it
			// takes this session with it - so note when the host last started, restart it, and
			// reconnect until it reports a newer start and is live again.
			key := "agent_start_time"
			if rebootHost {
				key = "boot_time"
			}
			otherConfig, err := xenapi.Host.GetOtherConfig(session, hostRef)
			check(err)
			before := otherConfig[key]
			if rebootHost {
				check(xenapi.Host.Reboot(session, hostRef)) // reboot into the updated software
			} else {
				check(xenapi.Host.RestartAgent(session, hostRef))
			}
			session = waitForRestart(url, user, password, host.UUID, key, before)
		}
		enableWhenBooted(session, hostRef) // return the host to service
	}
	fmt.Println("OK: rolling-pool-update")
}
