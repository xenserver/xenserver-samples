package main

import (
	"fmt"

	"go/xenapi"
)

// hostPowerOn - Configure host power on.
//
// Set a host's out-of-band power-on mode and credentials, then read them back.
func hostPowerOn(url, user, password string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	hostRef := hosts[0]

	// Mode and config travel together: the config carries the credentials the mode needs.
	// "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/
	// "DRAC" modes were removed from the real power-on plugin and fail the moment host.power_on is
	// actually called ("{mode} script has been removed").
	check(xenapi.Host.SetPowerOnMode(session, hostRef, "wake-on-lan", map[string]string{}))
	mode, _ := xenapi.Host.GetPowerOnMode(session, hostRef)
	fmt.Printf("Power-on mode:  %s\n", mode)
	cfg, _ := xenapi.Host.GetPowerOnConfig(session, hostRef)
	for k, v := range cfg {
		fmt.Printf("  %s = %s\n", k, v)
	}

	check(xenapi.Host.SetPowerOnMode(session, hostRef, "", map[string]string{}))
	fmt.Println("OK: host-power-on")
	session.Logout()
}
