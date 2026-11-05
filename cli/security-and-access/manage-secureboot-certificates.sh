# Manage Secure Boot certificates.
#
# Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to use them,
# then flag a guest whose certificates have gone stale for a refresh at its next boot — and unflag it again.
#
# Run it:
#   ./workflows.sh manage-secureboot-certificates https://xenserver root "$password"

manage_secureboot_certificates() {
    # A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it was created.
    # Rotating the pool's leaves the guest's stale, and the fix is applied at the guest's next boot rather
    # than underneath a running VM - so you flag it and reboot when convenient.
    #
    # "ready_no_dbx" means the pool has the essentials but no revocation list - usable, and deliberately
    # not the same answer as "ready".
    echo "Pool Secure Boot readiness: $(xe pool-get-guest-secureboot-readiness)"
    pool=$(first_csv "$(xe pool-list --minimal)")
    if [ -n "$(xe pool-param-get uuid=$pool param-name=uefi-certificates)" ]; then holds=true; else holds=false; fi
    echo "  pool holds certificates:  $holds"

    # A guest whose certificates have gone stale. The state is a plain field, so it filters like any other.
    # This is a deliberately-seeded state, not one an ordinarily-provisioned pool is ever in - report and
    # stop cleanly when no VM needs it, rather than operating on an empty uuid.
    #
    # Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
    # BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
    # suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window.
    vm=$(first_csv "$(xe vm-list secureboot-certificates-state=update_available --minimal)")
    if [ -z "$vm" ]; then
        echo "No guest needs a Secure Boot certificate refresh right now."
        echo "OK: manage-secureboot-certificates"
        return
    fi
    echo "$(xe vm-param-get uuid=$vm param-name=name-label): readiness $(xe vm-get-secureboot-readiness uuid=$vm), certificates $(xe vm-param-get uuid=$vm param-name=secureboot-certificates-state)"

    # Flagging and unflagging are the same command with opposite values of mark=.
    xe vm-update-secureboot-certificates-on-boot uuid=$vm mark=true
    echo "  flagged for refresh:      $(xe vm-param-get uuid=$vm param-name=secureboot-certificates-state)"

    xe vm-update-secureboot-certificates-on-boot uuid=$vm mark=false
    echo "  unflagged:                $(xe vm-param-get uuid=$vm param-name=secureboot-certificates-state)"
    echo "OK: manage-secureboot-certificates"
}
