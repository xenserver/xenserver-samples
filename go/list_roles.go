package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// listRoles - List RBAC roles.
//
// Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to
// users.
//
// Run it:
//
//	listRoles("https://xenserver", "root", password)
func listRoles(url, user, password string) {
	session := connect(url, user, password)
	// Role is the one class XenCenter still bulk-downloads; RBAC subjects map to these roles. Role records
	// include every permission too; the roles a user can be granted are the ones made of permissions
	// (non-empty subroles), as xe role-list shows.
	roles, err := xenapi.Role.GetAllRecords(session)
	check(err)
	seen := map[string]bool{}
	var names []string
	for _, r := range roles {
		if len(r.Subroles) > 0 && !seen[r.NameLabel] {
			seen[r.NameLabel] = true
			names = append(names, r.NameLabel)
		}
	}
	shown := names
	if len(shown) > 8 {
		shown = shown[:8]
	}
	fmt.Printf("Roles (%d): %s\n", len(names), strings.Join(shown, ", "))
	fmt.Println("OK: list-roles")
	session.Logout()
}
