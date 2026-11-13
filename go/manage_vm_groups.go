package main

import (
	"fmt"

	"go/xenapi"
)

// manageVMGroups - Manage VM groups.
//
// Create an anti-affinity VM group, put a VM in it, read the membership back from the group side,
// then take the VM out again and delete the group.
func manageVMGroups(url, user, password, vmName, groupName string) {
	session := connect(url, user, password)
	vmRef := vmByName(session, vmName)

	// anti_affinity asks the pool to keep the group's members on different hosts.
	groupRef, err := xenapi.VMGroup.Create(session, xenapi.VMGroupRecord{
		NameLabel:       groupName,
		NameDescription: "Anti-affinity group created by the SDK example",
		Placement:       xenapi.PlacementPolicyAntiAffinity,
	})
	check(err)
	groupUUID, _ := xenapi.VMGroup.GetUUID(session, groupRef)
	fmt.Printf("Created group:  %s\n", groupUUID)

	// Membership is written from the VM side...
	check(xenapi.VM.SetGroups(session, vmRef, []xenapi.VMGroupRef{groupRef}))

	// ...and read back from the group side, which is the half that is easy to get wrong.
	members, err := xenapi.VMGroup.GetVMs(session, groupRef)
	check(err)
	fmt.Printf("Group members:  %d\n", len(members))
	for _, m := range members {
		name, _ := xenapi.VM.GetNameLabel(session, m)
		fmt.Printf("  %s\n", name)
	}

	// VM_group.destroy already clears the group from every member VM's groups field - no need to
	// remove membership ourselves first.
	check(xenapi.VMGroup.Destroy(session, groupRef))
	fmt.Println("OK: manage-vm-groups")
	session.Logout()
}
