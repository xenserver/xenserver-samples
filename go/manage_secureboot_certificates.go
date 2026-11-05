package main

import (
	"fmt"

	"go/xenapi"
)

// manageSecurebootCertificates - Manage Secure Boot certificates.
//
// Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to
// use them, then flag a guest whose certificates have gone stale for a refresh at its next boot —
// and unflag it again.
//
// Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
// BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
// suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window.
//
// Run it:
//
//	manageSecurebootCertificates("https://xenserver", "root", password)
func manageSecurebootCertificates(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	// A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it was
	// created. Rotating the pool's leaves the guest's stale, and the fix is applied at the guest's next
	// boot rather than underneath a running VM - so you flag it and reboot when convenient.
	//
	// First, whether the pool holds the certificates to hand out at all. "ready_no_dbx" means it has the
	// essentials but no revocation list - usable, and not the same answer as "ready".
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	readiness, err := xenapi.Pool.GetGuestSecurebootReadiness(session, pools[0])
	check(err)
	certs, err := xenapi.Pool.GetUefiCertificates(session, pools[0])
	check(err)
	fmt.Printf("Pool Secure Boot readiness: %s\n", readiness)
	fmt.Printf("  pool holds certificates:  %t\n", certs != "")

	// A guest whose certificates have gone stale. Its state is what a client gates the flag/unflag
	// actions on, so it is the field to watch. This is a deliberately-provisioned state, not one a
	// normally-provisioned Secure Boot guest is ever in - report and stop cleanly when no VM needs
	// it, rather than failing with a bare lookup error.
	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vm xenapi.VMRef
	var name string
	found := false
	for ref, r := range vms {
		if !r.IsATemplate && !r.IsControlDomain && !r.IsASnapshot &&
			r.SecurebootCertificatesState == xenapi.VMSecurebootCertificatesStateUpdateAvailable {
			vm, name, found = ref, r.NameLabel, true
			break
		}
	}
	if !found {
		fmt.Println("No guest needs a Secure Boot certificate refresh right now.")
		fmt.Println("OK: manage-secureboot-certificates")
		return
	}
	vmReadiness, err := xenapi.VM.GetSecurebootReadiness(session, vm)
	check(err)
	state, err := xenapi.VM.GetSecurebootCertificatesState(session, vm)
	check(err)
	fmt.Printf("%s: readiness %s, certificates %s\n", name, vmReadiness, state)

	// Flagging and unflagging are the same call with opposite booleans.
	check(xenapi.VM.UpdateSecurebootCertificatesOnBoot(session, vm, true))
	state, _ = xenapi.VM.GetSecurebootCertificatesState(session, vm)
	fmt.Printf("  flagged for refresh:      %s\n", state)

	check(xenapi.VM.UpdateSecurebootCertificatesOnBoot(session, vm, false))
	state, _ = xenapi.VM.GetSecurebootCertificatesState(session, vm)
	fmt.Printf("  unflagged:                %s\n", state)

	fmt.Println("OK: manage-secureboot-certificates")
}
