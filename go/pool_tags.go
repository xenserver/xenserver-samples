package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// poolTags - Tag the pool.
//
// Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and
// hosts.
//
// Run it:
//
//	poolTags("https://xenserver", "root", password)
func poolTags(url, user, password string) {
	session := connect(url, user, password)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	poolRef := pools[0]
	check(xenapi.Pool.AddTags(session, poolRef, "sdk-managed"))
	tags, _ := xenapi.Pool.GetTags(session, poolRef)
	fmt.Printf("Pool tags: %s\n", strings.Join(tags, ", "))
	check(xenapi.Pool.RemoveTags(session, poolRef, "sdk-managed"))
	fmt.Println("OK: pool-tags")
	session.Logout()
}
