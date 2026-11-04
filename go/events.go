package main

import (
	"fmt"

	"go/xenapi"
)

// events - Event monitoring.
//
// Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a
// client's view of the pool live.
//
// Run it:
//
//	events("https://xenserver", "root", password, "web-01")
func events(url, user, password, vmName string) {
	session := connect(url, user, password)
	classes := []string{"VM"}
	batch, err := xenapi.Event.From(session, classes, "", 1.0)
	check(err)
	token := batch.Token
	fmt.Println("Established event token after initial snapshot.")

	vmRef := vmByName(session, vmName)
	original, err := xenapi.VM.GetNameDescription(session, vmRef)
	check(err)
	check(xenapi.VM.SetNameDescription(session, vmRef, "changed-to-trigger-event"))

	batch, err = xenapi.Event.From(session, classes, token, 5.0)
	check(err)
	fmt.Printf("Received %d event(s) after the change.\n", len(batch.Events))
	for i, ev := range batch.Events {
		if i >= 3 {
			break
		}
		fmt.Printf("  - %s %s\n", ev.Operation, ev.Class)
	}

	check(xenapi.VM.SetNameDescription(session, vmRef, original)) // put it back
	fmt.Println("OK: events")
	session.Logout()
}
