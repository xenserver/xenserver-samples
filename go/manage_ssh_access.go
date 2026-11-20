package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// manageSSHAccess - Manage SSH access.
//
// Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it
// again — the pool-level call fans out to every host.
func manageSSHAccess(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	// Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
	before, err := xenapi.Host.GetAllRecords(session)
	check(err)

	// Timed access is the point: set the timeout first and the server stamps an expiry when SSH is
	// enabled, so a window opened for troubleshooting closes itself. This is itself a pool-wide
	// fan-out call, exactly like EnableSSH/DisableSSH - no need to loop hosts for it either.
	check(xenapi.Pool.SetSSHEnabledTimeout(session, pools[0], 3600))

	// The pool call fans out to every host, so there is no need to loop for the enable itself.
	check(xenapi.Pool.EnableSSH(session, pools[0]))
	for _, host := range hosts {
		record, err := xenapi.Host.GetRecord(session, host)
		check(err)
		fmt.Printf("%s: ssh enabled=%t, expires %s\n", record.NameLabel, record.SSHEnabled,
			record.SSHExpiry.UTC().Format("20060102T15:04:05Z"))
	}

	check(xenapi.Pool.DisableSSH(session, pools[0]))
	states := []string{}
	for _, host := range hosts {
		record, err := xenapi.Host.GetRecord(session, host)
		check(err)
		states = append(states, fmt.Sprintf("%s=%t", record.NameLabel, record.SSHEnabled))
	}
	fmt.Printf("After disable: %s\n", strings.Join(states, ", "))

	for host, record := range before {
		// first: enabling stamps the expiry from it
		check(xenapi.Host.SetSSHEnabledTimeout(session, host, record.SSHEnabledTimeout))
		if record.SSHEnabled {
			check(xenapi.Host.EnableSSH(session, host))
		}
	}
	fmt.Println("OK: manage-ssh-access")
}
