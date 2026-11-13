package main

import (
	"fmt"
	"sort"

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
	// A snapshot is a template too (is_a_template is set on every snapshot), so leave those out.
	var templates []xenapi.VMRecord
	for _, v := range vms {
		if v.IsATemplate && !v.IsASnapshot {
			templates = append(templates, v)
		}
	}
	sort.Slice(templates, func(i, j int) bool { return templates[i].NameLabel < templates[j].NameLabel })
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
