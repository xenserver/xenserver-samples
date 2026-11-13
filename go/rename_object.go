package main

import (
	"fmt"

	"go/xenapi"
)

// renameObject - Rename an object.
//
// Change an object's name and read it back — how any object is renamed.
//
// Run it:
//
//	renameObject("https://xenserver", "root", password, "web-01")
func renameObject(url, user, password, vmName string) {
	session := connect(url, user, password)
	vm := vmByName(session, vmName)
	original, _ := xenapi.VM.GetNameLabel(session, vm)
	check(xenapi.VM.SetNameLabel(session, vm, "sdk-renamed"))
	now, _ := xenapi.VM.GetNameLabel(session, vm)
	fmt.Printf("Renamed '%s' -> '%s'\n", original, now)
	check(xenapi.VM.SetNameLabel(session, vm, original)) // restore so the example is repeatable
	fmt.Println("OK: rename-object")
	session.Logout()
}
