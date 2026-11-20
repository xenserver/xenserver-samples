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
    Write-Host "Pool Secure Boot readiness: $(Get-XenPoolProperty -Ref $pool -XenProperty GuestSecurebootReadiness)"
    Write-Host "  pool holds certificates:  $([bool]$pool.uefi_certificates)"

    # A guest whose certificates have gone stale. secureboot_certificates_state is set on every VM
    # regardless of whether Secure Boot is actually on, so it alone isn't enough: readiness of "disabled"
    # or "not_supported" means this guest doesn't use Secure Boot at all, and flagging it for a refresh
    # would prove nothing.
    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.secureboot_certificates_state -eq 'update_available' -and
        (Get-XenVMProperty -Ref $_ -XenProperty SecurebootReadiness) -notin @('disabled', 'not_supported')
    } | Select-Object -First 1
    if (-not $vm) {
        Write-Host "No Secure Boot guest needs a certificate refresh right now."
        Write-Host "OK: manage-secureboot-certificates"
        $session | Disconnect-XenServer
        return
    }
    Write-Host ("{0}: readiness {1}, certificates {2}" -f $vm.name_label,
        (Get-XenVMProperty -Ref $vm -XenProperty SecurebootReadiness),
        (Get-XenVMProperty -Ref $vm -XenProperty SecurebootCertificatesState))

    # Flagging and unflagging are the same action with opposite values of -Mark.
    $vm | Invoke-XenVM -XenAction UpdateSecurebootCertificatesOnBoot -Mark $true
    Write-Host "  flagged for refresh:      $((Get-XenVM -Ref $vm).secureboot_certificates_state)"

    $vm | Invoke-XenVM -XenAction UpdateSecurebootCertificatesOnBoot -Mark $false
    Write-Host "  unflagged:                $((Get-XenVM -Ref $vm).secureboot_certificates_state)"

    Write-Host "OK: manage-secureboot-certificates"
    $session | Disconnect-XenServer
}
