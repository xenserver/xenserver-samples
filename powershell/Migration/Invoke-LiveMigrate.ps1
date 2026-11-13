function Invoke-LiveMigrate {
    <#
    .SYNOPSIS
        Live migrate a VM.
    .DESCRIPTION
        Move a running VM to another host in the pool with no downtime: check the destination can boot it,
        live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and PV
        drivers (source_vm), with its disks moved first to a shared storage repository (sr_name) so the
        destination host can see them.
    .EXAMPLE
        Invoke-LiveMigrate -Url https://xenserver -UserName root -Password $password -SourceVm 'web-01' -SrName 'Shared NFS'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [Parameter(Mandatory = $true)][string]$SrName,
        [string]$NewVmName = "sdk-example-migrate"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Live migration needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so this moves a
    # throwaway copy of SourceVm, a VM with a guest OS and PV drivers. Only the VM's memory moves, so the
    # destination host has to see its disks already: a disk on local storage refuses with VM_REQUIRES_SR.
    # Put the copy's disks on the shared SR SrName first.
    $sr = Get-XenSR -Name $SrName | Where-Object { $_.shared } | Select-Object -First 1
    if (-not $sr) { throw "No shared SR named '$SrName' was found." }
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm
    Move-DisksToSr -VmRef $ref -SrRef $sr
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref

    $sourceHostRef = (Get-XenVM -Ref $ref).resident_on
    Write-Host "VM is running on: $((Get-XenHost -Ref $sourceHostRef).name_label)"

    # Pick a different host in the pool to receive the VM.
    $destHost = Get-XenHost | Where-Object { $sourceHostRef -ne $_ } | Select-Object -First 1

    # Check the destination can boot it, then live-migrate. Both are native cmdlet actions: the
    # destination host is passed as -XenHost and the (empty) options map as -Options.
    $vm | Invoke-XenVM -XenAction AssertCanBootHere -XenHost $destHost
    $vm | Invoke-XenVM -XenAction PoolMigrate -XenHost $destHost -Options @{}  # @{} = default live migration

    Write-Host "Migrated to:      $((Get-XenHost -Ref (Get-XenVM -Ref $ref).resident_on).name_label)"
    Write-Host "Still running:    $((Get-XenVM -Ref $ref).power_state)"

    # Tidy up so the example is repeatable.
    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $vm
    Write-Host "OK: live-migrate"
    $session | Disconnect-XenServer
}
