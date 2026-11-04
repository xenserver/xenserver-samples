package main

import (
	"fmt"

	"go/xenapi"
)

// configurePoolOptions - Configure pool options.
//
// Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping
// and memory-migration compression — then put them back.
//
// Run it:
//
//	configurePoolOptions("https://xenserver", "root", password)
func configurePoolOptions(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]

	// None of these is a wizard: they are plain pool settings that a client exposes on a properties
	// page, and each is a single field. Read them, change them, put them back.
	livePatching, err := xenapi.Pool.GetLivePatchingDisabled(session, pool)
	check(err)
	igmp, err := xenapi.Pool.GetIgmpSnoopingEnabled(session, pool)
	check(err)
	migrationCompression, err := xenapi.Pool.GetMigrationCompression(session, pool)
	check(err)
	fmt.Printf("  %-22s %t\n", "live patching disabled", livePatching)
	fmt.Printf("  %-22s %t\n", "IGMP snooping", igmp)
	fmt.Printf("  %-22s %t\n", "migration compression", migrationCompression)

	// Live patching applies host updates without a reboot; disabling it forces the reboot.
	check(xenapi.Pool.SetLivePatchingDisabled(session, pool, !livePatching))
	// IGMP snooping keeps multicast off ports that did not ask for it.
	check(xenapi.Pool.SetIgmpSnoopingEnabled(session, pool, !igmp))
	// Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
	check(xenapi.Pool.SetMigrationCompression(session, pool, !migrationCompression))

	fmt.Println("after changing:")
	after1, _ := xenapi.Pool.GetLivePatchingDisabled(session, pool)
	after2, _ := xenapi.Pool.GetIgmpSnoopingEnabled(session, pool)
	after3, _ := xenapi.Pool.GetMigrationCompression(session, pool)
	fmt.Printf("  %-22s %t\n", "live patching disabled", after1)
	fmt.Printf("  %-22s %t\n", "IGMP snooping", after2)
	fmt.Printf("  %-22s %t\n", "migration compression", after3)

	check(xenapi.Pool.SetLivePatchingDisabled(session, pool, livePatching))
	check(xenapi.Pool.SetIgmpSnoopingEnabled(session, pool, igmp))
	check(xenapi.Pool.SetMigrationCompression(session, pool, migrationCompression))
	fmt.Println("  restored")
	fmt.Println("OK: configure-pool-options")
}
