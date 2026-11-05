function Invoke-ManageSecurebootCertificates {
    <#
    .SYNOPSIS
        Manage Secure Boot certificates.
    .DESCRIPTION
        Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to use
        them, then flag a guest whose certificates have gone stale for a refresh at its next boot — and
        unflag it again.

        Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
        BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
        suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window.
    .EXAMPLE
        Invoke-ManageSecurebootCertificates -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    # A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it was created.
    # Rotating the pool's leaves the guest's stale, and the fix is applied at the guest's next boot rather
    # than underneath a running VM - so you flag it and reboot when convenient.
    #
    # First, whether the pool holds the certificates to hand out at all. "ready_no_dbx" means it has the
    # essentials but no revocation list - usable, and not the same answer as "ready".
    Write-Host "Pool Secure Boot readiness: $(Get-XenPoolProperty -Ref $pool.opaque_ref -XenProperty GuestSecurebootReadiness)"
    Write-Host "  pool holds certificates:  $([bool]$pool.uefi_certificates)"

    # A guest whose certificates have gone stale. Its state is what a client gates the flag/unflag actions
    # on, so it is the field to watch.
    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.secureboot_certificates_state -eq 'update_available'
    } | Select-Object -First 1
    if (-not $vm) {
        # This state only occurs on a VM whose UEFI certificates are out of date, not on a normally
        # provisioned pool. Report cleanly instead of letting a bare "no such element" lookup error
        # propagate.
        Write-Host "No guest needs a Secure Boot certificate refresh right now."
        Write-Host "OK: manage-secureboot-certificates"
        $session | Disconnect-XenServer
        return
    }
    Write-Host ("{0}: readiness {1}, certificates {2}" -f $vm.name_label,
        (Get-XenVMProperty -Ref $vm.opaque_ref -XenProperty SecurebootReadiness),
        (Get-XenVMProperty -Ref $vm.opaque_ref -XenProperty SecurebootCertificatesState))

    # Flagging and unflagging are the same action with opposite values of -Mark.
    $vm | Invoke-XenVM -XenAction UpdateSecurebootCertificatesOnBoot -Mark $true
    Write-Host "  flagged for refresh:      $((Get-XenVM -Ref $vm.opaque_ref).secureboot_certificates_state)"

    $vm | Invoke-XenVM -XenAction UpdateSecurebootCertificatesOnBoot -Mark $false
    Write-Host "  unflagged:                $((Get-XenVM -Ref $vm.opaque_ref).secureboot_certificates_state)"

    Write-Host "OK: manage-secureboot-certificates"
    $session | Disconnect-XenServer
}
