function Invoke-ManageVtpm {
    <#
    .SYNOPSIS
        Manage a virtual TPM.
    .DESCRIPTION
        Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one,
        and only while it is halted.
    .EXAMPLE
        Invoke-ManageVtpm -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # vTPM is not supported for a BIOS-mode VM, only a UEFI one (HVM_boot_params["firmware"] ==
    # "uefi"), so pick one of those rather than any halted VM.
    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.power_state -eq 'Halted' -and $_.VTPMs.Count -eq 0 -and
        $_.HVM_boot_params['firmware'] -eq 'uefi'
    } | Select-Object -First 1
    if (-not $vm) { throw "No halted UEFI VM without a vTPM already attached was found." }
    Write-Host "Attaching a vTPM to $($vm.name_label)"

    # IsUnique false: the vTPM may be copied along with the VM. A VM may have at most one, and it can
    # only be attached while Halted — the device is presented at boot.
    $vtpm = New-XenVTPM -VM $vm.opaque_ref -IsUnique $false -PassThru
    Write-Host "  persistence backend: $($vtpm.persistence_backend)"
    Write-Host "  unique to this VM:   $($vtpm.is_unique)"
    Write-Host "  VM now has $(@((Get-XenVM -Ref $vm.opaque_ref).VTPMs).Count) vTPM(s)"

    # The VM advertises whether another can be added; once it has one, it cannot.
    Write-Host "  can add another:     $((Get-XenVM -Ref $vm.opaque_ref).allowed_operations -contains 'create_vtpm')"

    Remove-XenVTPM -Ref $vtpm.opaque_ref
    Write-Host "  after removal:       $(@((Get-XenVM -Ref $vm.opaque_ref).VTPMs).Count) vTPM(s)"
    Write-Host "OK: manage-vtpm"
    $session | Disconnect-XenServer
}
