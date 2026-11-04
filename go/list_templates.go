package main

import (
	"fmt"

	"go/xenapi"
)

// listTemplates - List templates.
//
// Enumerate the pool's VM templates, both built-in and custom.
//
// Run it:
//
//	listTemplates("https://xenserver", "root", password)
func listTemplates(url, user, password string) {
	session := connect(url, user, password)
	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var templates []xenapi.VMRecord
	for _, v := range vms {
		if v.IsATemplate {
			templates = append(templates, v)
		}
	}
	fmt.Printf("Templates (%d):\n", len(templates))
	for i, t := range templates {
		if i >= 8 {
			break
		}
		badge := ""
		if _, ok := t.OtherConfig["default_template"]; ok {
			badge = " [built-in]"
		}
		fmt.Printf("  - %s%s\n", t.NameLabel, badge)
	}
	fmt.Println("OK: list-templates")
	session.Logout()
}
