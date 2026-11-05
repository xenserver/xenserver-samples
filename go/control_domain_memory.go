package main

import (
	"fmt"

	"go/xenapi"
)

// controlDomainMemory - Change control domain memory.
//
// Read and change a host's control domain (dom0) memory, then put it back. One setter pins the
// static and dynamic bounds together, because dom0 does not balloon.
func controlDomainMemory(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	dom0, ok := controlDomainOf(session, hosts[0])
	if !ok {
		panic("the host reports no control domain")
	}

	original, err := xenapi.VM.GetMemoryDynamicMin(session, dom0)
	check(err)
	name, _ := xenapi.Host.GetNameLabel(session, hosts[0])
	fmt.Printf("%s dom0: %.1f GiB\n", name, float64(original)/(1024*1024*1024))

	// One setter, not a range: dom0 does not balloon, so SetMemory pins the static and dynamic bounds
	// and the target together. The new size takes effect at the next reboot, so change it with the
	// host in maintenance mode — the API itself does not stop you.
	check(xenapi.VM.SetMemory(session, dom0, original+1024*1024*1024))
	record, err := xenapi.VM.GetRecord(session, dom0)
	check(err)
	fmt.Printf("  now %.1f GiB (static %d-%d, dynamic %d-%d)\n",
		float64(record.MemoryDynamicMin)/(1024*1024*1024),
		record.MemoryStaticMin, record.MemoryStaticMax,
		record.MemoryDynamicMin, record.MemoryDynamicMax)

	check(xenapi.VM.SetMemory(session, dom0, original)) // leave the pool as we found it
	fmt.Println("OK: control-domain-memory")
}

func controlDomainOf(session *xenapi.Session, host xenapi.HostRef) (xenapi.VMRef, bool) {
	vms, err := xenapi.Host.GetResidentVMs(session, host)
	check(err)
	for _, vm := range vms {
		isDom0, err := xenapi.VM.GetIsControlDomain(session, vm)
		check(err)
		if isDom0 {
			return vm, true
		}
	}
	return "", false
}
