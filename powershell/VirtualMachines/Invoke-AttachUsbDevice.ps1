function Invoke-AttachUsbDevice {
    <#
    .SYNOPSIS
        Attach a USB device to a VM.
    .DESCRIPTION
        List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it
        again.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = "web-01"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName

    $pusb = Get-XenPUSB | Select-Object -First 1
    Write-Host "Device:         $($pusb.description)"

    # Passthrough is off until an administrator releases the device: attaching one that has not been
    # released fails rather than silently doing nothing.
    Set-XenPUSB -PUSB $pusb -PassthroughEnabled $true

    $vusb = New-XenVUSB -VM $vm -USBGroup $pusb.USB_group -PassThru
    Write-Host "Attached:       $(@((Get-XenVM -Name $VmName).VUSBs).Count) device(s)"

    # Destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM it gets
    # plugged in as soon as it's created, so unplug it first.
    if ((Get-XenVUSB -Ref $vusb).currently_attached) {
        Invoke-XenVUSB -Ref $vusb -XenAction Unplug
    }
    Remove-XenVUSB -VUSB $vusb
    Set-XenPUSB -PUSB (Get-XenPUSB | Select-Object -First 1) -PassthroughEnabled $false
    Write-Host "OK: attach-usb-device"
    $session | Disconnect-XenServer
}
