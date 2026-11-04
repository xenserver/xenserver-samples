package main

import (
	"fmt"

	"go/xenapi"
)

// connectInventory - Connect & inventory.
//
// Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the
// virtual machines with their power state. This is the starting point for every session.
//
// Run it:
//
//	connectInventory("https://xenserver", "root", password)
func connectInventory(url, user, password string) {
	session := connect(url, user, password)
	pools, err := xenapi.Pool.GetAllRecords(session)
	check(err)
	for _, pool := range pools {
		fmt.Printf("Connected to pool: %s\n", pool.NameLabel)
		break
	}

	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	fmt.Printf("Hosts (%d):\n", len(hosts))
	for _, host := range hosts {
		fmt.Printf("  - %s (%s)\n", host.NameLabel, host.Address)
	}

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	count := 0
	for _, vm := range vms {
		if !vm.IsATemplate && !vm.IsControlDomain {
			count++
			fmt.Printf("  - %s [%s]\n", vm.NameLabel, vm.PowerState)
		}
	}
	fmt.Printf("VMs (%d)\n", count)

	fmt.Println("OK: connect-inventory")
	session.Logout()
}
