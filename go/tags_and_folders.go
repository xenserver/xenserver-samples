package main

import (
	"fmt"

	"go/xenapi"
)

// tagsAndFolders - Tag and organize objects.
//
// Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object
// type), place the VM in a folder, read it all back, then tidy up.
//
// Run it:
//
//	tagsAndFolders("https://xenserver", "root", password, "web-01")
func tagsAndFolders(url, user, password, vmName string) {
	session := connect(url, user, password)
	vm := vmByName(session, vmName)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	host := hosts[0]

	// Tags work on any object type (VM, host, SR, network, …).
	check(xenapi.VM.AddTags(session, vm, "web"))
	check(xenapi.Host.AddTags(session, host, "gold"))
	vmTags, _ := xenapi.VM.GetTags(session, vm)
	hostTags, _ := xenapi.Host.GetTags(session, host)
	fmt.Printf("VM tags:   %v\n", vmTags)
	fmt.Printf("Host tags: %v\n", hostTags)

	// Folder placement lives in other_config["folder"] as a leading-slash path.
	check(xenapi.VM.AddToOtherConfig(session, vm, "folder", "/Production/Web"))
	oc, _ := xenapi.VM.GetOtherConfig(session, vm)
	fmt.Printf("VM folder: %s\n", oc["folder"])

	check(xenapi.VM.RemoveTags(session, vm, "web"))
	check(xenapi.Host.RemoveTags(session, host, "gold"))
	check(xenapi.VM.RemoveFromOtherConfig(session, vm, "folder"))
	fmt.Println("OK: tags-and-folders")
	session.Logout()
}
