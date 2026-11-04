package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// configureNrpe - Configure NRPE monitoring.
//
// Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read
// its status and configuration, enable it and permit a monitoring host, then read it back.
//
// host.call_plugin is per-host - there is no pool-wide fan-out for plugin calls the way there is
// for pool.enable_ssh - so configure every host in the pool, and restore each one to disabled
// again afterwards.
func configureNrpe(url, user, password string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	for _, host := range hosts {
		nrpe := func(fn string, args map[string]string) string {
			r, e := xenapi.Host.CallPlugin(session, host, "nrpe", fn, args)
			check(e)
			return r
		}
		label, _ := xenapi.Host.GetNameLabel(session, host)
		fmt.Printf("%s: NRPE status before: %s\n", label, strings.TrimSpace(nrpe("status", map[string]string{})))
		nrpe("enable", map[string]string{})
		nrpe("set-config", map[string]string{"allowed_hosts": "127.0.0.1,::1,192.0.2.60", "debug": "0", "ssl_logging": "0x00"})
		nrpe("restart", map[string]string{})
		fmt.Printf("  status after:  %s\n", strings.TrimSpace(nrpe("status", map[string]string{})))
		for _, line := range strings.Split(nrpe("get-config", map[string]string{}), "\n") {
			if strings.HasPrefix(line, "allowed_hosts:") {
				fmt.Printf("  allowed hosts: %s\n", strings.TrimSpace(strings.SplitN(line, ":", 2)[1]))
			}
		}
		nrpe("disable", map[string]string{}) // restore: leave it as we found it
	}
	fmt.Println("OK: configure-nrpe")
	session.Logout()
}
