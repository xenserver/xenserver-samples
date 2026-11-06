function Invoke-ManageVmDisks {
    <#
    .SYNOPSIS
        Manage VM disks.
    .DESCRIPTION
        Deactivate a running VM's disk, resize it, reactivate it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [Parameter(Mandatory = $true)][string]$SrName,
        [string]$NewVmName = "sdk-example-vm-disks"
    )
    # Not the VM's root/boot disk: a real VM's system disk is Unpluggable=false (only a template's
    # non-system disks default to unpluggable), so Unplug on it fails on a real host with
    # VBD_NOT_UNPLUGGABLE - and the VM has to be running in the first place, or unplug fails with
    # VM_BAD_POWER_STATE. Work on a data disk this example adds to its own throwaway VM instead,
    # and tidy up afterwards so the example is repeatable. No shrink: real SR backends refuse one
    # outright (SR_BACKEND_FAILURE_79), so this only ever grows.
    #
    # Plugging and unplugging a disk on a running VM needs the guest's PV drivers
    # (VM_MISSING_PV_DRIVERS otherwise), so the VM is a throwaway copy of SourceVm, a VM with a guest OS
    # and PV drivers.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref

    $sr = Get-XenSR -Name $SrName | Select-Object -First 1
    if (-not $sr) { throw "No SR named '$SrName' was found." }
    $vdi = New-XenVDI -NameLabel "sdk-example-data-disk" -SR $sr -VirtualSize 4GB `
        -Type user -Sharable $false -ReadOnly $false -PassThru
    $device = (Get-XenVMProperty -Ref $ref -XenProperty AllowedVBDDevices)[0]
    $vbd = New-XenVBD -VM (Get-XenVM -Ref $ref) -VDI $vdi -Userdevice $device -Bootable $false `
        -Mode RW -Type Disk -Empty $false -PassThru
    $vbd | Invoke-XenVBD -XenAction Plug
    Write-Host "Disk attached:  $((Get-XenVBD -Ref $vbd).currently_attached)"

    # Deactivate = VBD.unplug. The disk stays with the VM; it is just no longer live.
    Invoke-XenVBD -Ref $vbd -XenAction Unplug
    Write-Host "After unplug:   $((Get-XenVBD -Ref $vbd).currently_attached)"

    $size = (Get-XenVDI -Ref $vdi).virtual_size
    Invoke-XenVDI -Ref $vdi -XenAction Resize -Size ([int64]$size * 2)
    Write-Host "Resized:        $size -> $((Get-XenVDI -Ref $vdi).virtual_size) bytes"

    Invoke-XenVBD -Ref $vbd -XenAction Plug
    Write-Host "After plug:     $((Get-XenVBD -Ref $vbd).currently_attached)"

    # Growing a disk that is attached and live is a DIFFERENT action, not a flag on the same one:
    # ResizeOnline tells the storage layer the guest is using the disk while it grows. Only some
    # storage drivers can (none of a stock XenServer 9's do), and the rest refuse with
    # SR_OPERATION_NOT_SUPPORTED - so ask the SR's driver (its SM record's features) first.
    $srType = (Get-XenSR -Ref $sr).type
    $features = (Get-XenSM | Where-Object { $_.type -eq $srType } | Select-Object -First 1).features
    if ($features -and $features.ContainsKey("VDI_RESIZE_ONLINE")) {
        $grown = [int64](Get-XenVDI -Ref $vdi).virtual_size + 1GB
        Invoke-XenVDI -Ref $vdi -XenAction ResizeOnline -Size $grown
        Write-Host "Grown online:   $((Get-XenVDI -Ref $vdi).virtual_size) bytes"
    }
    else {
        Write-Host "Grown online:   not supported by $srType storage; unplug, resize, plug as above"
    }

    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $ref
    Write-Host "OK: manage-vm-disks"
    Disconnect-XenServer -Session $session
}
