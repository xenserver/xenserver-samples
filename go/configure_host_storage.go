package main

import (
	"fmt"

	"go/xenapi"
)

// configureHostStorage - Configure host storage.
//
// Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.
//
// The IQN identifies this host to iSCSI targets, so a target's access list is written against it -
// changing it on a host with live iSCSI storage cuts it off. Multipathing uses every path to the
// storage rather than one, and on real hardware you put the host into maintenance mode before
// changing it, because the paths are rebuilt.
//
// Run it:
//
//	configureHostStorage("https://xenserver", "root", password)
func configureHostStorage(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	hostName, err := xenapi.Host.GetNameLabel(session, host)
	check(err)

	beforeIqn, err := xenapi.Host.GetIscsiIqn(session, host)
	check(err)
	beforeMultipathing, err := xenapi.Host.GetMultipathing(session, host)
	check(err)
	fmt.Printf("%s: iSCSI IQN %q, multipathing %t\n", hostName, beforeIqn, beforeMultipathing)

	check(xenapi.Host.SetIscsiIqn(session, host, "iqn.2026-01.com.example:"+hostName))
	check(xenapi.Host.SetMultipathing(session, host, true))
	iqn, _ := xenapi.Host.GetIscsiIqn(session, host)
	multipathing, _ := xenapi.Host.GetMultipathing(session, host)
	fmt.Printf("  IQN now:      %s\n", iqn)
	fmt.Printf("  multipathing: %t\n", multipathing)

	// set_iscsi_iqn refuses an empty string (INVALID_VALUE) - only restore it if this host actually
	// had one set before; a host that has never had an IQN configured can't be "restored" to empty.
	if beforeIqn != "" {
		check(xenapi.Host.SetIscsiIqn(session, host, beforeIqn))
	}
	check(xenapi.Host.SetMultipathing(session, host, beforeMultipathing))
	fmt.Println("  restored")
	fmt.Println("OK: configure-host-storage")
}
