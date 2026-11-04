function Invoke-ManageVmMedia {
    <#
    .SYNOPSIS
        Manage a VM's CD drive.
    .DESCRIPTION
        Add a DVD drive to a VM, insert an ISO from the library and eject it again.
    .EXAMPLE
        Invoke-ManageVmMedia -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.power_state -eq 'Halted'
    } | Select-Object -First 1
    Write-Host "Adding a DVD drive to $($vm.name_label)"

    # A CD drive is a VBD like any other, distinguished by Type CD; the media is whichever VDI it points
    # at, and an empty drive points at none.
    $device = @(Get-XenVMProperty -Ref $vm.opaque_ref -XenProperty AllowedVBDDevices)[0]
    $drive = New-XenVBD -VM $vm -Userdevice $device -Bootable $false -Mode RO -Type CD `
        -Empty $true -Unpluggable $true -OtherConfig @{} -QosAlgorithmType '' `
        -QosAlgorithmParams @{} -PassThru
    Write-Host "  drive $device is empty: $((Get-XenVBD -Ref $drive.opaque_ref).empty)"

    # The ISO library is an SR of content type "iso"; its VDIs are the available images.
    $isoSr = Get-XenSR | Where-Object { $_.content_type -eq 'iso' -and $_.type -ne 'udev' } |
        Select-Object -First 1
    $iso = $isoSr.VDIs | ForEach-Object { Get-XenVDI -Ref $_.opaque_ref } |
        Sort-Object name_label | Select-Object -First 1
    Write-Host "  inserting $($iso.name_label)"
    Invoke-XenVBD -Ref $drive.opaque_ref -XenAction Insert -Vdi $iso

    $loaded = Get-XenVBD -Ref $drive.opaque_ref
    Write-Host ("  drive now holds {0} (empty={1})" -f
        (Get-XenVDI -Ref $loaded.VDI.opaque_ref).name_label, $loaded.empty)

    Invoke-XenVBD -Ref $drive.opaque_ref -XenAction Eject
    Write-Host "  after eject, empty=$((Get-XenVBD -Ref $drive.opaque_ref).empty)"

    Remove-XenVBD -Ref $drive.opaque_ref
    Write-Host "OK: manage-vm-media"
    $session | Disconnect-XenServer
}
