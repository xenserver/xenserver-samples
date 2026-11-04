package main

import (
	"fmt"

	"go/xenapi"
)

// listNetworks - List networks.
//
// Enumerate the pool's networks with their physical and virtual interface counts.
//
// Run it:
//
//	listNetworks("https://xenserver", "root", password)
func listNetworks(url, user, password string) {
	session := connect(url, user, password)
	nets, err := xenapi.Network.GetAllRecords(session)
	check(err)
	fmt.Printf("Networks (%d):\n", len(nets))
	for _, net := range nets {
		fmt.Printf("  - %s: %d PIF(s), %d VIF(s)\n", net.NameLabel, len(net.PIFs), len(net.VIFs))
	}
	fmt.Println("OK: list-networks")
	session.Logout()
}
