function Invoke-AttachExistingDisk {
    <#
    .SYNOPSIS
        Attach an existing disk to another VM.
    .DESCRIPTION
        Move a disk between VMs by detaching and re-attaching it, without copying the data.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk between VMs
    # is removing one VBD and creating another - no copying, and the data stays exactly where it is.
    $halted = @(Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.power_state -eq 'Halted'
    })
    $sr = Get-XenSR | Where-Object {
        $_.shared -and $_.content_type -ne 'iso' -and $_.type -notin @('iso', 'udev')
    } | Select-Object -First 1

    $vdi = New-XenVDI -SR $sr -NameLabel 'sdk-example-portable-disk' -VirtualSize 4GB `
        -Type User -Sharable $false -ReadOnly $false -PassThru
    Write-Host "Disk $($vdi.name_label) created on $($sr.name_label)"

    $vbd = Add-ExampleDisk -VM $halted[0] -Vdi $vdi
    Write-Host "  attached to $($halted[0].name_label)"

    # Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
    Remove-XenVBD -Ref $vbd
    Write-Host "  detached:   the disk still exists ($((Get-XenVDI -Ref $vdi).virtual_size) bytes)"

    Add-ExampleDisk -VM $halted[1] -Vdi $vdi | Out-Null
    Write-Host "  attached to $($halted[1].name_label)"
    $vbds = @((Get-XenVDI -Ref $vdi).VBDs)
    Write-Host "  the disk is on $($vbds.Count) VM(s)"

    foreach ($b in $vbds) { Remove-XenVBD -Ref $b }
    Remove-XenVDI -Ref $vdi
    Write-Host "OK: attach-existing-disk"
    $session | Disconnect-XenServer
}

function Add-ExampleDisk {
    <#
    .SYNOPSIS
        Join an existing disk to a VM on its next free device slot.
    #>
    param($VM, $Vdi)
    New-XenVBD -VM $VM -VDI $Vdi -Userdevice (Get-XenVMProperty -Ref $VM -XenProperty AllowedVBDDevices)[0] `
        -Mode RW -Type Disk -Bootable $false -Empty $false -PassThru
}
