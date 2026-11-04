package main

import (
	"fmt"

	"go/xenapi"
)

// readMetrics - Read host & VM metrics.
//
// Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
//
// Run it:
//
//	readMetrics("https://xenserver", "root", password)
func readMetrics(url, user, password string) {
	const MiB = 1024 * 1024

	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var hostRef xenapi.HostRef
	var hostName string
	for ref, h := range hosts {
		hostRef, hostName = ref, h.NameLabel
		break
	}
	hm, err := xenapi.Host.GetMetrics(session, hostRef)
	check(err)
	total, _ := xenapi.HostMetrics.GetMemoryTotal(session, hm)
	free, _ := xenapi.Host.ComputeFreeMemory(session, hostRef)
	live, _ := xenapi.HostMetrics.GetLive(session, hm)
	fmt.Printf("Host %s: %d MiB total, %d MiB free, live = %v\n",
		hostName, total/MiB, free/MiB, live)

	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vmRef xenapi.VMRef
	for ref, v := range vms {
		if !v.IsATemplate && !v.IsControlDomain && v.PowerState == xenapi.VMPowerStateRunning {
			vmRef = ref
			break
		}
	}
	vmm, err := xenapi.VM.GetMetrics(session, vmRef)
	check(err)
	vcpus, _ := xenapi.VMMetrics.GetVCPUsNumber(session, vmm)
	mem, _ := xenapi.VMMetrics.GetMemoryActual(session, vmm)
	name, _ := xenapi.VM.GetNameLabel(session, vmRef)
	fmt.Printf("VM %s: %d vCPU(s), %d MiB\n", name, vcpus, mem/MiB)
	fmt.Println("OK: read-metrics")
	session.Logout()
}
