package main

import (
	"fmt"

	"go/xenapi"
)

// poolProperties - Pool properties.
//
// Read the pool name and default storage repository, then rename the pool and restore it.
//
// Run it:
//
//	poolProperties("https://xenserver", "root", password)
func poolProperties(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	poolRef := pools[0]
	original, _ := xenapi.Pool.GetNameLabel(session, poolRef)
	defaultSR, _ := xenapi.Pool.GetDefaultSR(session, poolRef)
	srName := "(none)"
	if isSet(defaultSR) {
		srName, _ = xenapi.SR.GetNameLabel(session, defaultSR)
	}
	fmt.Printf("Pool:       '%s'\n", original)
	fmt.Printf("Default SR: %s\n", srName)

	check(xenapi.Pool.SetNameLabel(session, poolRef, "sdk-pool-renamed"))
	now, _ := xenapi.Pool.GetNameLabel(session, poolRef)
	fmt.Printf("Renamed to: '%s'\n", now)
	check(xenapi.Pool.SetNameLabel(session, poolRef, original)) // restore
	fmt.Println("OK: pool-properties")
}
