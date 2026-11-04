function Invoke-AttachDisk {
    <#
    .SYNOPSIS
        Attach a new disk.
    .DESCRIPTION
        Create a fresh virtual disk on a storage repository and attach it to a VM.
    .EXAMPLE
        Invoke-AttachDisk -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8' -SrName 'Shared NFS'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [Parameter(Mandatory = $true)][string]$SrName,
        [string]$NewVmName = "sdk-example-attachdisk"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm.opaque_ref
    $ref = $vm.opaque_ref
    $sr = Get-XenSR -Name $SrName | Select-Object -First 1
    if (-not $sr) { throw "No SR named '$SrName' was found." }

    # Create a fresh VDI on the SR and attach it as a new VBD (a new virtual disk).
    $vdi = New-XenVDI -NameLabel "sdk-example-data-disk" -SR $sr -VirtualSize 8GB `
        -Type user -Sharable $false -ReadOnly $false -PassThru
    $device = (Get-XenVMProperty -Ref $ref -XenProperty AllowedVBDDevices)[0]
    New-XenVBD -VM (Get-XenVM -Ref $ref) -VDI $vdi -Userdevice $device -Bootable $false `
        -Mode RW -Type Disk -Empty $false | Out-Null
    Write-Host "Attached an 8 GiB disk on $($sr.name_label) as device $device"
    Write-Host "VM now has $(@((Get-XenVM -Ref $ref).VBDs).Count) VBD(s)"

    # Tidy up: destroy the VM (which removes its VBDs) and then its disks (Remove-XenVM leaves VDIs
    # behind), including the one just attached.
    Remove-VmAndDisks -Ref $ref
    Write-Host "OK: attach-disk"
    $session | Disconnect-XenServer
}
