package main

import (
	"fmt"

	"go/xenapi"
)

// configureSyslog - Send logs to a remote syslog server.
//
// Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the
// setting is recorded but nothing changes.
//
// Two steps, and the second is the one that is easy to miss: setting the destination only records
// it, and the host keeps logging locally until the syslog daemon is reconfigured to pick the setting
// up.
func configureSyslog(url, user, password, syslogServer string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	hostName, err := xenapi.Host.GetNameLabel(session, host)
	check(err)

	logging, err := xenapi.Host.GetLogging(session, host)
	check(err)
	fmt.Printf("%s logging: %s\n", hostName, loggingOrLocal(logging))

	check(xenapi.Host.RemoveFromLogging(session, host, "syslog_destination"))
	check(xenapi.Host.AddToLogging(session, host, "syslog_destination", syslogServer))
	check(xenapi.Host.SyslogReconfigure(session, host))
	logging, _ = xenapi.Host.GetLogging(session, host)
	fmt.Printf("  now logging to: %s\n", logging["syslog_destination"])

	check(xenapi.Host.RemoveFromLogging(session, host, "syslog_destination"))
	check(xenapi.Host.SyslogReconfigure(session, host))
	logging, _ = xenapi.Host.GetLogging(session, host)
	fmt.Printf("  restored: %s\n", loggingOrLocal(logging))
	fmt.Println("OK: configure-syslog")
}

// loggingOrLocal renders a host's logging map, or "(local only)" once it is empty.
func loggingOrLocal(logging map[string]string) string {
	if len(logging) == 0 {
		return "(local only)"
	}
	return fmt.Sprintf("%v", logging)
}
