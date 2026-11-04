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
    $ref = $vm.opaque_ref
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref

    $vdiRef = (Get-XenVM -Ref $ref).VBDs |
        ForEach-Object { Get-XenVBD -Ref $_.opaque_ref } |
        Where-Object { $_.type -eq 'Disk' } |
        ForEach-Object { $_.VDI.opaque_ref } |
        Select-Object -First 1
    $sourceSr = (Get-XenVDI -Ref $vdiRef).SR.opaque_ref
    Write-Host "Disk is on SR: $((Get-XenSR -Ref $sourceSr).name_label)"

    # Pick a different SR that holds disks and that the VM's host can reach (a currently-attached PBD
    # there).
    $vmHost = (Get-XenVM -Ref $ref).resident_on.opaque_ref
    $reachableSrs = @(Get-XenPBD | Where-Object { $_.host.opaque_ref -eq $vmHost -and $_.currently_attached } |
        ForEach-Object { $_.SR.opaque_ref })
    $destSr = Get-XenSR | Where-Object {
        $_.opaque_ref -ne $sourceSr -and $_.content_type -ne 'iso' -and $_.type -notin @('iso', 'udev') -and
        $reachableSrs -contains $_.opaque_ref
    } | Select-Object -First 1

    # PoolMigrate returns the disk's new VDI: the copy on the destination SR replaces the original.
    $vdiRef = (Get-XenVDI -Ref $vdiRef | Invoke-XenVDI -XenAction PoolMigrate -SR $destSr -Options @{} -PassThru).opaque_ref

    $nowOn = (Get-XenVDI -Ref $vdiRef).SR.opaque_ref
    Write-Host "Disk moved to:  $((Get-XenSR -Ref $nowOn).name_label)"

    # Tidy up: the VM and the disks it now owns.
    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $ref
    Write-Host "OK: storage-migrate"
    $session | Disconnect-XenServer
}
