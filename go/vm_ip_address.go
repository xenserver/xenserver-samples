package main

import (
	"fmt"
	"strconv"
	"time"

	"go/xenapi"
)

// vmIpAddress - Get a VM's IP address.
//
// Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.
//
// A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
// empty networks map) - retry for a while before concluding it has no guest agent reporting.
// timeoutStr and intervalStr take seconds, as decimal strings (Go's dispatcher passes key=value
// arguments as strings).
func vmIpAddress(url, user, password, vmName, timeoutStr, intervalStr string) {
	timeout, err := strconv.Atoi(timeoutStr)
	check(err)
	interval, err := strconv.Atoi(intervalStr)
	check(err)
	session := connect(url, user, password)
	vm := vmByName(session, vmName)

	deadline := time.Now().Add(time.Duration(timeout) * time.Second)
	var ip string
	for {
		// An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
		record, err := xenapi.VM.GetRecord(session, vm)
		check(err)
		ip = ""
		if record.PowerState == xenapi.VMPowerStateRunning && isSet(record.GuestMetrics) {
			gm, err := xenapi.VMGuestMetrics.GetRecord(session, record.GuestMetrics)
			check(err)
			ip = gm.Networks["0/ip"]
		}
		if ip != "" || time.Now().After(deadline) {
			break
		}
		time.Sleep(time.Duration(interval) * time.Second)
	}
	if ip != "" {
		fmt.Printf("  %s: %s\n", vmName, ip)
	} else {
		fmt.Printf("  %s: no IP address reported yet (no guest agent running?)\n", vmName)
	}
	fmt.Println("OK: vm-ip-address")
	session.Logout()
}
