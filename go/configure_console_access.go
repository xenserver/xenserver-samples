package main

import (
	"fmt"

	"go/xenapi"
)

// configureConsoleAccess - Configure console access.
//
// Tighten how consoles and management traffic may be used: idle timeouts for the pool's own
// consoles and for VM consoles, one session at a time, and refusing plain HTTP.
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

	// NB: pool.https_only and pool.console_idle_timeout are SET below but never read back. SDK 26.14
	// generates a setter and no getter for both (unlike host.console_idle_timeout, which has both), so
	// they cannot be read through the typed bindings at all - and a sample that reached past its own
	// binding to show a value would be teaching a workaround rather than the API.
	vmConsoleTimeout, err := xenapi.Pool.GetVMConsoleIdleTimeout(session, pool)
	check(err)
	limitSessions, err := xenapi.Pool.GetLimitConsoleSessions(session, pool)
	check(err)
	hostTimeout, err := xenapi.Host.GetConsoleIdleTimeout(session, host)
	check(err)
	fmt.Printf("  %-26s %ds\n", "VM console idle timeout", vmConsoleTimeout)
	fmt.Printf("  %-26s %t\n", "limit console sessions", limitSessions)
	fmt.Printf("  %-26s %ds\n", "host console idle timeout", hostTimeout)

	// Ten minutes of inactivity, one console session at a time, and no plain HTTP.
	check(xenapi.Pool.SetConsoleIdleTimeout(session, pool, 600))
	check(xenapi.Pool.SetVMConsoleIdleTimeout(session, pool, 600))
	check(xenapi.Pool.SetLimitConsoleSessions(session, pool, true))
	check(xenapi.Host.SetConsoleIdleTimeout(session, host, 300))
	check(xenapi.Pool.SetHTTPSOnly(session, pool, true))

	fmt.Println("after tightening:")
	vmConsoleTimeout, _ = xenapi.Pool.GetVMConsoleIdleTimeout(session, pool)
	limitSessions, _ = xenapi.Pool.GetLimitConsoleSessions(session, pool)
	hostTimeout, _ = xenapi.Host.GetConsoleIdleTimeout(session, host)
	fmt.Printf("  %-26s %ds\n", "VM console idle timeout", vmConsoleTimeout)
	fmt.Printf("  %-26s %t\n", "limit console sessions", limitSessions)
	fmt.Printf("  %-26s %ds\n", "host console idle timeout", hostTimeout)

	check(xenapi.Pool.SetHTTPSOnly(session, pool, false))
	check(xenapi.Pool.SetConsoleIdleTimeout(session, pool, 0))
	check(xenapi.Pool.SetVMConsoleIdleTimeout(session, pool, 0))
	check(xenapi.Pool.SetLimitConsoleSessions(session, pool, false))
	check(xenapi.Host.SetConsoleIdleTimeout(session, host, 0))
	fmt.Println("  restored")
	fmt.Println("OK: configure-console-access")
}
