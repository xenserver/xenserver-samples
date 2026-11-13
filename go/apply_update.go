package main

import (
	"fmt"

	"go/xenapi"
)

// applyUpdate - Apply updates from the CDN.
//
// Sync the pool's update metadata from the CDN and apply it to every host, starting with the pool
// coordinator, then read each host's post-update reboot guidance.
//
// Host.ApplyUpdates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
// Workload Balancing to be switched off before you start updating - so check both up front and stop
// rather than disabling either for you; turn them back on again once the update is done.
//
// pool.sync_updates needs at least one repository with update=true enabled
// (NO_REPOSITORY_ENABLED otherwise) - introduce and attach a throwaway one, and forget it again
// afterwards. Applying a batch whose mandatory guidance needs an evacuation fails with
// HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs are moved off first; handle that
// rather than assuming an update batch never asks for one. Guidance that targets VMs instead of
// hosts (for example restarting a VM) is not handled here.
func applyUpdate(url, user, password, repoURL, sourceURL string) {
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

	// Sync the pool's update metadata; the returned hash identifies the synced set.
	hash, err := xenapi.Pool.SyncUpdates5(session, pool, false, "", "")
	check(err)
	fmt.Printf("Synced updates; hash length %d\n", len(hash))

	// Apply the synced updates to each host, coordinator first as the documentation requires.
	// Then read the reboot guidance to decide whether a host needs a reboot.
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
		if _, err := xenapi.Host.ApplyUpdates(session, hostRef, hash); err != nil {
			if failureCode(err) != xenapi.ErrorHostEvacuationIsRequired {
				panic(err)
			}
			fmt.Printf("  %s: needs evacuating first; evacuating and retrying\n", host.NameLabel)
			check(xenapi.Host.Disable(session, hostRef, true))
			check(xenapi.Host.Evacuate2(session, hostRef))
			_, err := xenapi.Host.ApplyUpdates(session, hostRef, hash)
			check(err)
			check(xenapi.Host.Enable(session, hostRef))
		}
		guidance, _ := xenapi.Host.GetPendingGuidances(session, hostRef)
		fmt.Printf("  %s: applied; pending guidance = %v\n", host.NameLabel, guidance)
		// Modern xapi (>=23.18.0) doesn't reboot a host for you: it only records pending_guidances,
		// so only reboot (or restart the toolstack) when the applied batch actually asks for it.
		rebootHost := containsGuidance(guidance, xenapi.UpdateGuidancesRebootHost)
		if rebootHost || containsGuidance(guidance, xenapi.UpdateGuidancesRestartToolstack) {
			// As in rolling-pool-update: either restart returns before it has happened, and the
			// coordinator's takes this session with it - so wait for it, reconnecting.
			key := "agent_start_time"
			if rebootHost {
				key = "boot_time"
			}
			otherConfig, err := xenapi.Host.GetOtherConfig(session, hostRef)
			check(err)
			before := otherConfig[key]
			if rebootHost {
				check(xenapi.Host.Reboot(session, hostRef))
			} else {
				check(xenapi.Host.RestartAgent(session, hostRef))
			}
			session = waitForRestart(url, user, password, host.UUID, key, before)
		}
		// apply_updates disables the host while it works (auto_enable: a restart puts it back) - with
		// no restart to do, nothing re-enables it. Return it to service either way.
		enableWhenBooted(session, hostRef)
	}
	fmt.Println("OK: apply-update")
}
