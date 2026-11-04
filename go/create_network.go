package main

import (
	"fmt"

	"go/xenapi"
)

// createNetwork - Create a network.
//
// Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to
// each other privately.
//
// Run it:
//
//	createNetwork("https://xenserver", "root", password, "sdk-example-net")
func createNetwork(url, user, password, networkName string) {
	session := connect(url, user, password)
	netRef, err := xenapi.Network.Create(session, xenapi.NetworkRecord{
		NameLabel:       networkName,
		NameDescription: "Internal network created by the SDK example",
		MTU:             1500,
		OtherConfig:     map[string]string{},
		// Managed by xapi (bridge and PIFs created for it). Say so: the binding sends every field, and
		// the zero value is false - an unmanaged network, which a bond refuses.
		Managed: true,
	})
	check(err)
	uuid, _ := xenapi.Network.GetUUID(session, netRef)
	fmt.Printf("Created network: %s\n", uuid)

	// Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this is a
	// property of the network rather than of any one interface on it.
	check(xenapi.Network.SetMTU(session, netRef, 9000))
	mtu, _ := xenapi.Network.GetMTU(session, netRef)
	fmt.Printf("MTU now:         %d\n", mtu)

	check(xenapi.Network.Destroy(session, netRef))
	fmt.Println("OK: create-network")
	session.Logout()
}
