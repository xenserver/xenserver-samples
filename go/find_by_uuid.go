package main

import (
	"fmt"

	"go/xenapi"
)

// findByUUID - Look up an object by UUID.
//
// Resolve a stable UUID back to a live object reference — how to persist a reference to an object
// across sessions.
func findByUUID(url, user, password, vmName string) {
	session := connect(url, user, password)
	// UUIDs are stable identifiers you can persist and resolve back to a (session-scoped) ref.
	vm := vmByName(session, vmName)
	uuid, _ := xenapi.VM.GetUUID(session, vm)
	resolved, err := xenapi.VM.GetByUUID(session, uuid)
	check(err)
	name, _ := xenapi.VM.GetNameLabel(session, resolved)
	fmt.Printf("UUID %s resolves to %s\n", uuid, name)
	fmt.Printf("Same object: %v\n", resolved == vm)
	fmt.Println("OK: find-by-uuid")
	session.Logout()
}
