package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// createBond - Create a NIC bond.
//
// Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond
// back, then dissolve it.
func createBond(url, user, password string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)

	// Pick up any NIC racked since the host booted. Cheap, and without it a card added a moment
	// ago is not there to bond.
	check(xenapi.PIF.Scan(session, hosts[0]))

	// Spare NICs only. A bond that includes the management interface moves the management address onto
	// the bond master — on a real host that is how you lose the connection you are working over.
	pifs, err := xenapi.PIF.GetAllRecords(session)
	check(err)
	var spares []xenapi.PIFRef
	var devices []string
	for ref, pif := range pifs {
		if pif.Host == hosts[0] && !pif.Management && pif.Physical && len(spares) < 2 {
			spares = append(spares, ref)
			devices = append(devices, pif.Device)
		}
	}
	if len(spares) < 2 {
		name, _ := xenapi.Host.GetNameLabel(session, hosts[0])
		panic(fmt.Sprintf("%s has %d spare NIC(s); a bond needs two that aren't the management interface",
			name, len(spares)))
	}
	fmt.Printf("Bonding:      %s\n", strings.Join(devices, ", "))

	// The bond needs a network to sit on.
	network, err := xenapi.Network.Create(session, xenapi.NetworkRecord{
		NameLabel:       "sdk-example-bond",
		NameDescription: "Created by the SDK example",
		Managed:         true, // as in createNetwork: the zero value would be NETWORK_UNMANAGED
	})
	check(err)

	// The Go binding's Create carries the properties map the other bindings default for you.
	bond, err := xenapi.Bond.Create(session, network, spares, "", xenapi.BondModeBalanceSlb,
		map[string]string{})
	check(err)
	master, _ := xenapi.Bond.GetMaster(session, bond)
	masterDev, _ := xenapi.PIF.GetDevice(session, master)
	mode, _ := xenapi.Bond.GetMode(session, bond)
	fmt.Printf("Bond master:  %s\n", masterDev)
	fmt.Printf("Mode:         %s\n", mode)

	check(xenapi.Bond.Destroy(session, bond))
	check(xenapi.Network.Destroy(session, network))
	left, _ := xenapi.Bond.GetAll(session)
	fmt.Printf("Bonds left:   %d\n", len(left))
	fmt.Println("OK: create-bond")
	session.Logout()
}
