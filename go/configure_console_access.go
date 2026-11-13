package main

import (
	"fmt"

	"go/xenapi"
)

// configureConsoleAccess - Configure console access.
//
// Tighten how consoles and management traffic may be used: idle timeouts for the pool's own
// consoles and for VM consoles, one session at a time, and refusing plain HTTP. Restore every
// value it changed afterwards.
//
// Idle console sessions are set at two levels - the pool's own management consoles and the VM
// consoles it serves - and a host can override the pool's. Requiring HTTPS refuses plain HTTP to the
// management interface altogether.
//
// Run it:
//
//	configureConsoleAccess("https://xenserver", "root", password)
func configureConsoleAccess(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	host, err := xenapi.Pool.GetMaster(session, pool)
	check(err)

	// NB: pool.https_only and pool.console_idle_timeout are SET below but never read back AT THE POOL
	// LEVEL. SDK 26.14 generates a setter and no getter for either there, because both are really
	// fan-outs that call the equivalent Host.Set* on every host rather than pool fields of their own.
	// host.https_only and host.console_idle_timeout ARE ordinary readable fields, so read this host's
	// values back through them instead, to show the effect and to know what to restore.
	beforeVMConsoleTimeout, err := xenapi.Pool.GetVMConsoleIdleTimeout(session, pool)
	check(err)
	beforeLimitSessions, err := xenapi.Pool.GetLimitConsoleSessions(session, pool)
	check(err)
	beforeHostTimeout, err := xenapi.Host.GetConsoleIdleTimeout(session, host)
	check(err)
	beforeHostHTTPSOnly, err := xenapi.Host.GetHTTPSOnly(session, host)
	check(err)
	fmt.Printf("  %-26s %ds\n", "VM console idle timeout", beforeVMConsoleTimeout)
	fmt.Printf("  %-26s %t\n", "limit console sessions", beforeLimitSessions)
	fmt.Printf("  %-26s %ds\n", "host console idle timeout", beforeHostTimeout)
	fmt.Printf("  %-26s %t\n", "host https only", beforeHostHTTPSOnly)

	// Ten minutes of inactivity, one console session at a time, and no plain HTTP.
	check(xenapi.Pool.SetConsoleIdleTimeout(session, pool, 600))
	check(xenapi.Pool.SetVMConsoleIdleTimeout(session, pool, 600))
	check(xenapi.Pool.SetLimitConsoleSessions(session, pool, true))
	check(xenapi.Host.SetConsoleIdleTimeout(session, host, 300))
	check(xenapi.Pool.SetHTTPSOnly(session, pool, true))

	fmt.Println("after tightening:")
	vmConsoleTimeout, _ := xenapi.Pool.GetVMConsoleIdleTimeout(session, pool)
	limitSessions, _ := xenapi.Pool.GetLimitConsoleSessions(session, pool)
	hostTimeout, _ := xenapi.Host.GetConsoleIdleTimeout(session, host)
	hostHTTPSOnly, _ := xenapi.Host.GetHTTPSOnly(session, host)
	fmt.Printf("  %-26s %ds\n", "VM console idle timeout", vmConsoleTimeout)
	fmt.Printf("  %-26s %t\n", "limit console sessions", limitSessions)
	fmt.Printf("  %-26s %ds\n", "host console idle timeout", hostTimeout)
	fmt.Printf("  %-26s %t\n", "host https only", hostHTTPSOnly)

	check(xenapi.Pool.SetHTTPSOnly(session, pool, beforeHostHTTPSOnly))
	check(xenapi.Pool.SetConsoleIdleTimeout(session, pool, beforeHostTimeout))
	check(xenapi.Pool.SetVMConsoleIdleTimeout(session, pool, beforeVMConsoleTimeout))
	check(xenapi.Pool.SetLimitConsoleSessions(session, pool, beforeLimitSessions))
	check(xenapi.Host.SetConsoleIdleTimeout(session, host, beforeHostTimeout))
	fmt.Println("  restored")
	fmt.Println("OK: configure-console-access")
}
