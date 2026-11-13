package main

import (
	"fmt"
	"sort"

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
	ordered := make([]xenapi.NetworkRecord, 0, len(nets))
	for _, net := range nets {
		ordered = append(ordered, net)
	}
	sort.Slice(ordered, func(i, j int) bool { return ordered[i].NameLabel < ordered[j].NameLabel })
	fmt.Printf("Networks (%d):\n", len(ordered))
	for _, net := range ordered {
		fmt.Printf("  - %s: %d PIF(s), %d VIF(s)\n", net.NameLabel, len(net.PIFs), len(net.VIFs))
	}
	fmt.Println("OK: list-networks")
	session.Logout()
}
