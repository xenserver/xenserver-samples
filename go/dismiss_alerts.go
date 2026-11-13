package main

import (
	"fmt"
	"sort"

	"go/xenapi"
)

// dismissAlerts - Raise and dismiss alerts.
//
// List the pool's alerts, then dismiss one — what the Notifications view does.
func dismissAlerts(url, user, password string) {
	session := connect(url, user, password)
	messages, err := xenapi.Message.GetAllRecords(session)
	check(err)
	fmt.Printf("Alerts:         %d\n", len(messages))

	if len(messages) == 0 {
		fmt.Println("No alerts to dismiss.")
	} else {
		// Sorted, for a deterministic choice of which one to dismiss.
		refs := make([]string, 0, len(messages))
		for ref := range messages {
			refs = append(refs, string(ref))
		}
		sort.Strings(refs)
		ref := xenapi.MessageRef(refs[0])
		m := messages[ref]
		fmt.Printf("Dismissing:     %s (priority %d)\n", m.Name, m.Priority)
		check(xenapi.Message.Destroy(session, ref))
		left, _ := xenapi.Message.GetAllRecords(session)
		fmt.Printf("Alerts left:    %d\n", len(left))
	}
	fmt.Println("OK: dismiss-alerts")
	session.Logout()
}
