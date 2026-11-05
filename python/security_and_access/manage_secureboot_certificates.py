"""Manage Secure Boot certificates.

Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to use
them, then flag a guest whose certificates have gone stale for a refresh at its next boot — and
unflag it again.

Run it::

    manage_secureboot_certificates("https://xenserver", "root", password)
"""

from connection import connect


def manage_secureboot_certificates(url, username, password):
    """Check UEFI Secure Boot readiness, then flag a guest for a certificate refresh.

    A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it
    was created. Rotating the pool's leaves the guest's stale, and the fix is applied at the
    guest's next boot rather than underneath a running VM -- so you flag it and reboot when
    convenient. Flagging and unflagging are the same call with opposite booleans.

    The precondition is the part worth being honest about: this needs a VM whose Secure Boot
    certificates are already due to refresh (secureboot_certificates_state == update_available).
    That's a deliberately-provisioned state, not one a normally-provisioned Secure Boot guest is
    ever in - so report and stop cleanly when no VM needs it, rather than failing with a bare
    lookup error.

    Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
    BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
    suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    # Whether the pool holds the certificates to hand out at all. "ready_no_dbx" means it has
    # the essentials but no revocation list -- usable, and not the same answer as "ready".
    print("Pool Secure Boot readiness: %s" % x.pool.get_guest_secureboot_readiness(pool))
    print("  pool holds certificates:  %s" % bool(x.pool.get_uefi_certificates(pool)))

    # A guest whose certificates have gone stale. Its state is what a client gates the
    # flag/unflag actions on, so it is the field to watch.
    vm = next((ref for ref, r in x.VM.get_all_records().items()
               if not r["is_a_template"] and not r["is_control_domain"] and not r["is_a_snapshot"]
               and r["secureboot_certificates_state"] == "update_available"), None)
    if vm is None:
        print("No guest needs a Secure Boot certificate refresh right now.")
        print("OK: manage-secureboot-certificates")
        session.logout()
        return
    print("%s: readiness %s, certificates %s"
          % (x.VM.get_name_label(vm), x.VM.get_secureboot_readiness(vm),
             x.VM.get_secureboot_certificates_state(vm)))

    x.VM.update_secureboot_certificates_on_boot(vm, True)
    print("  flagged for refresh:      %s" % x.VM.get_secureboot_certificates_state(vm))

    x.VM.update_secureboot_certificates_on_boot(vm, False)
    print("  unflagged:                %s" % x.VM.get_secureboot_certificates_state(vm))

    print("OK: manage-secureboot-certificates")
    session.logout()
