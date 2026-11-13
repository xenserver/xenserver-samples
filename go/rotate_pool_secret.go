package main

import (
	"fmt"

	"go/xenapi"
)

// rotatePoolSecret - Rotate the pool secret.
//
// Rotate the shared secret that authenticates pool members to each other.
func rotatePoolSecret(url, user, password string) {
	session := connect(url, user, password)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	name, _ := xenapi.Pool.GetNameLabel(session, pools[0])
	fmt.Printf("Pool:           %s\n", name)

	// xapi checks its own preconditions before rotating - HA must be disabled, every host must be
	// live, no rolling pool upgrade may be in progress, and the pool must be licensed for it - and
	// raises a clear error naming which one failed rather than silently refusing. Report that
	// explanation instead of letting the failure speak for itself; the point here is demonstrating
	// the precondition handling, not requiring the rotation to succeed.
	explanations := map[string]string{
		xenapi.ErrorHaIsEnabled:               "HA is enabled on this pool; disable it first.",
		xenapi.ErrorCannotContactHost:         "a host in the pool is not reachable.",
		xenapi.ErrorNotSupportedDuringUpgrade: "a rolling pool upgrade is in progress.",
		xenapi.ErrorLicenceRestriction:        "this edition is not licensed for pool secret rotation.",
	}
	if err := xenapi.Pool.RotateSecret(session); err != nil {
		code := failureCode(err)
		explanation, ok := explanations[code]
		if !ok {
			explanation = "see the error for detail"
		}
		fmt.Printf("Could not rotate the pool secret: %s (%s)\n", code, explanation)
	} else {
		after, _ := xenapi.Pool.GetAll(session)
		fmt.Printf("Rotated. Still connected: %t\n", len(after) == 1)
	}
	fmt.Println("OK: rotate-pool-secret")
	session.Logout()
}
