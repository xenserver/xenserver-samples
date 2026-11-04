package main

import (
	"fmt"

	"go/xenapi"
)

// rollingPoolUpdate needs an enabled update repository the same way apply-update does - introduce
// and attach a throwaway one, forget it again afterwards. Modern xapi (>=23.18.0) doesn't reboot a
// host for you: it only records pending_guidances, so only reboot (or restart the toolstack) when
// the applied batch actually asks for it.
func rollingPoolUpdate(url, user, password, repoURL, sourceURL string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
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

	// The rolling pattern behind XenCenter's automated Install Updates:
	// disable -> evacuate -> apply -> reboot (only if asked) -> re-enable, one host at a time.
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	for hostRef, host := range hosts {
		fmt.Printf("Updating %s:\n", host.NameLabel)
		check(xenapi.Host.Disable(session, hostRef, false)) // stop new VMs landing here
		check(xenapi.Host.Evacuate2(session, hostRef))      // move running guests to the rest of the pool
		_, err := xenapi.Host.ApplyUpdates(session, hostRef, hash)
		check(err) // apply the synced updates
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
