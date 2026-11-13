package main

import (
	"fmt"

	"go/xenapi"
)

// hostInfo - Host information.
//
// Read a host's software version, edition and CPU topology (sockets and cores).
//
// Run it:
//
//	hostInfo("https://xenserver", "root", password)
func hostInfo(url, user, password string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var host xenapi.HostRecord
	for _, h := range hosts {
		host = h
		break
	}

	// A map lookup that falls back to "?" for a key the host does not report.
	get := func(m map[string]string, key string) string {
		if v, ok := m[key]; ok {
			return v
		}
		return "?"
	}

	fmt.Printf("Host:     %s\n", host.NameLabel)
	fmt.Printf("Version:  %s\n", get(host.SoftwareVersion, "product_version"))
	fmt.Printf("Edition:  %s\n", host.Edition)
	fmt.Printf("CPUs:     %s across %s socket(s)\n",
		get(host.CPUInfo, "cpu_count"), get(host.CPUInfo, "socket_count"))
	// The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what you
	// quote to the hardware vendor, so it is the one field here that identifies this machine, not its model.
	fmt.Printf("Hardware: %s %s\n", get(host.BiosStrings, "system-manufacturer"),
		get(host.BiosStrings, "system-product-name"))
	fmt.Printf("Serial:   %s\n", get(host.BiosStrings, "system-serial-number"))
	fmt.Printf("BIOS:     %s\n", get(host.BiosStrings, "bios-version"))
	fmt.Println("OK: host-info")
	session.Logout()
}
