package main

import (
	"fmt"
	"strconv"
	"time"

	"go/xenapi"
)

// vmIpAddress - Get a VM's IP address.
//
// Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
//
// A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
// empty networks map) - retry for a while rather than giving up on the first look. timeoutStr and
// intervalStr take seconds, as decimal strings (Go's dispatcher passes key=value arguments as strings).
func vmIpAddress(url, user, password, timeoutStr, intervalStr string) {
	timeout, err := strconv.Atoi(timeoutStr)
	check(err)
	interval, err := strconv.Atoi(intervalStr)
	check(err)
	session := connect(url, user, password)

	deadline := time.Now().Add(time.Duration(timeout) * time.Second)
	for {
		// A running guest reports its IP in VM_guest_metrics.networks, keyed "<vif device>/ip".
		vms, err := xenapi.VM.GetAllRecords(session)
		check(err)
		// Not every running VM has one (no guest tools, no NIC, still booting), so look at each until one
		// does.
		var vm xenapi.VMRecord
		var ip string
		for _, r := range vms {
			if r.PowerState != xenapi.VMPowerStateRunning || r.IsATemplate || r.IsControlDomain ||
				r.GuestMetrics == xenapi.VMGuestMetricsRef("OpaqueRef:NULL") {
				continue
			}
			gm, err := xenapi.VMGuestMetrics.GetRecord(session, r.GuestMetrics)
			check(err)
			if ip = gm.Networks["0/ip"]; ip != "" {
				vm = r
				break
			}
		}
		if ip != "" {
			fmt.Printf("  %s: %s\n", vm.NameLabel, ip)
			break
		}
		if time.Now().After(deadline) {
			panic(fmt.Sprintf("no running guest reported an IP address within %ds", timeout))
		}
		time.Sleep(time.Duration(interval) * time.Second)
	}
	fmt.Println("OK: vm-ip-address")
	session.Logout()
}
