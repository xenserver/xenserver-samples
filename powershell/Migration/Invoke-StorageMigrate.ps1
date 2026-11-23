function Invoke-StorageMigrate {
    <#
    .SYNOPSIS
        Storage live-migration.
    .DESCRIPTION
        Move a running VM's virtual disk to a different storage repository while the VM keeps running — live
        storage migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
    .EXAMPLE
        Invoke-StorageMigrate -Url https://xenserver -UserName root -Password $password -SourceVm 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [string]$NewVmName = "sdk-example-storagemigrate"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so
    # this works on a throwaway copy of SourceVm, a VM with a guest OS and PV drivers. (A halted VM's disk
    # moves too, without the guest; what VDI PoolMigrate always needs is a VM to move the disk for - a VDI
    # no VBD points at fails VDI_NEEDS_VM_FOR_MIGRATE.)
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref

    $vdiRef = (Get-XenVM -Ref $ref).VBDs |
        ForEach-Object { Get-XenVBD -Ref $_ } |
        Where-Object { $_.type -eq 'Disk' } |
        ForEach-Object { $_.VDI } |
        Select-Object -First 1
    $sourceSr = (Get-XenVDI -Ref $vdiRef).SR
    Write-Host "Disk is on SR: $((Get-XenSR -Ref $sourceSr).name_label)"

    # Pick a different SR that holds disks, that the VM's host can reach (a currently-attached PBD
    # there), and that has room for the disk - a host's local SR is often too small for a VM's disk.
    # Scan a candidate before trusting its free space: the size and utilisation xapi reports are only
    # as fresh as the SR's last scan, and can claim room the storage doesn't have. Live storage
    # migration copies a snapshot of the disk and mirrors the running disk on top of it, so the
    # destination needs room for the disk twice over (a thick-provisioned LVM SR allocates both).
    $vmHost = (Get-XenVM -Ref $ref).resident_on
    $diskSize = [long](Get-XenVDI -Ref $vdiRef).virtual_size
    $reachableSrs = @(Get-XenPBD | Where-Object { $_.host -eq $vmHost -and $_.currently_attached } |
        ForEach-Object { $_.SR })
    $destSr = Get-XenSR | Where-Object {
        $sourceSr -ne $_ -and $_.content_type -ne 'iso' -and $_.type -notin @('iso', 'udev') -and
        $reachableSrs -contains $_
    } | Where-Object {
        $_ | Invoke-XenSR -XenAction Scan
        $scanned = Get-XenSR -Ref $_
        ([long]$scanned.physical_size - [long]$scanned.physical_utilisation) -ge 2 * $diskSize
    } | Select-Object -First 1
    if (-not $destSr) {
        $vm | Invoke-XenVM -XenAction HardShutdown
        Remove-VmAndDisks -Ref $ref
        throw "no other SR attached to $((Get-XenHost -Ref $vmHost).name_label) has room for the " +
            "$([math]::Floor($diskSize / 1GB)) GiB disk twice over"
    }

    # PoolMigrate returns the disk's new VDI: the copy on the destination SR replaces the original.
    $vdiRef = Get-XenVDI -Ref $vdiRef | Invoke-XenVDI -XenAction PoolMigrate -SR $destSr -Options @{} -PassThru

    $nowOn = (Get-XenVDI -Ref $vdiRef).SR
    Write-Host "Disk moved to:  $((Get-XenSR -Ref $nowOn).name_label)"

    # Tidy up: the VM and the disks it now owns.
    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $ref
    Write-Host "Cleaned up the example VM."
    Write-Host "OK: storage-migrate"
    $session | Disconnect-XenServer
}
