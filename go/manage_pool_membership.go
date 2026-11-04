package main

import (
	"fmt"
	"time"

	"go/xenapi"
)

// managePoolMembership lists the pool's hosts, promotes a different coordinator, then promotes
// the original back. designate_new_master runs a two-phase commit across every host and ends by
// restarting xapi pool-wide (the new coordinator becomes master, every other host becomes its
// slave) - so the session this call was made on, and the connection itself, do not survive it.
// Reconnect (with a bounded wait) before touching the pool again, rather than assuming the session
// is still good, and re-resolve pool/host refs from the fresh session each time.
func managePoolMembership(url, user, password string) {
	session := connect(url, user, password)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)

	original, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	name, _ := xenapi.Host.GetNameLabel(session, original)
	fmt.Printf("Coordinator: %s\n", name)

	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	var other xenapi.HostRef
	for _, h := range hosts {
		hn, _ := xenapi.Host.GetNameLabel(session, h)
		suffix := ""
		if h == original {
			suffix = " (coordinator)"
		} else {
			other = h
		}
		fmt.Printf("  member: %s%s\n", hn, suffix)
	}
	otherName, _ := xenapi.Host.GetNameLabel(session, other)
	otherUUID, _ := xenapi.Host.GetUUID(session, other)
	originalUUID, _ := xenapi.Host.GetUUID(session, original)

	// Promote another member. The pool database moves with the role and clients are redirected, so this
	// briefly interrupts management traffic — it does not move any VM.
	check(xenapi.Pool.DesignateNewMaster(session, other))
	fmt.Printf("Promoting:   %s (xapi restarts pool-wide; reconnecting)\n", otherName)

	session = reconnectAfterMasterChange(url, user, password, otherUUID)
	pools, err = xenapi.Pool.GetAll(session)
	check(err)
	master, _ := xenapi.Pool.GetMaster(session, pools[0])
	masterName, _ := xenapi.Host.GetNameLabel(session, master)
	fmt.Printf("Promoted:    %s\n", masterName)

	// Put it back. Ejecting a member (Pool.Eject) is the other half of this surface and is deliberately
	// not shown: it cannot be undone from the pool, because rejoining is initiated by the ejected host.
	check(xenapi.Pool.DesignateNewMaster(session, original))
	fmt.Printf("Restoring:   %s (reconnecting again)\n", name)

	session = reconnectAfterMasterChange(url, user, password, originalUUID)
	pools, err = xenapi.Pool.GetAll(session)
	check(err)
	master, _ = xenapi.Pool.GetMaster(session, pools[0])
	masterName, _ = xenapi.Host.GetNameLabel(session, master)
	fmt.Printf("Restored:    %s\n", masterName)

	fmt.Println("OK: manage-pool-membership")
	session.Logout()
}

// reconnectAfterMasterChange waits out a pool-wide xapi restart (pool.DesignateNewMaster) and
// reconnects.
//
// DesignateNewMaster returns BEFORE the change: for a while the old coordinator still answers, and
// still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not
// enough - keep reconnecting until the pool names the new coordinator (by uuid; connect follows
// HOST_IS_SLAVE to wherever the coordinator now is). That can take minutes.
func reconnectAfterMasterChange(url, user, password, newMasterUUID string) (session *xenapi.Session) {
	deadline := time.Now().Add(600 * time.Second)
	var lastErr any
	for time.Now().Before(deadline) {
		settled := func() (ok bool) {
			defer func() {
				if r := recover(); r != nil {
					lastErr = r
					ok = false
				}
			}()
			session = connect(url, user, password)
			pools, err := xenapi.Pool.GetAll(session)
			check(err)
			master, err := xenapi.Pool.GetMaster(session, pools[0])
			check(err)
			uuid, err := xenapi.Host.GetUUID(session, master)
			check(err)
			// The new coordinator answers before the pool has settled - calls made too soon fail
			// (HANDLE_INVALID on the operation's own task) - so also wait for every host to be back,
			// live and enabled.
			if uuid != newMasterUUID {
				lastErr = "the pool has not settled under the new coordinator"
				return false
			}
			hosts, err := xenapi.Host.GetAllRecords(session)
			check(err)
			for _, h := range hosts {
				live, err := xenapi.HostMetrics.GetLive(session, h.Metrics)
				check(err)
				if !h.Enabled || !live {
					lastErr = "the pool has not settled under the new coordinator"
					return false
				}
			}
			return true
		}()
		if settled {
			return session
		}
		if session != nil {
			session.Logout()
		}
		time.Sleep(5 * time.Second)
	}
	panic(fmt.Sprintf("the pool did not come back after the master change: %v", lastErr))
}
