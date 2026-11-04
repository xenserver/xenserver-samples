function Invoke-CheckpointVm {
    <#
    .SYNOPSIS
        Checkpoint & revert.
    .DESCRIPTION
        Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
        you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works
        on a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
    .EXAMPLE
        Invoke-CheckpointVm -Url https://xenserver -UserName root -Password $password -SourceVm 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [string]$NewVmName = "sdk-example-checkpoint"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
    # Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), hence a copy of
    # SourceVm - a VM with a guest OS and PV drivers - rather than an OS-less template clone.
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm.opaque_ref
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref

    $checkpoint = $vm | Invoke-XenVM -XenAction Checkpoint -NewName "sdk-example-checkpoint-1" -PassThru
    Write-Host "Created checkpoint: $($checkpoint.uuid)"
    Write-Host "is_a_snapshot = $($checkpoint.is_a_snapshot)"

    $vm | Invoke-XenVM -XenAction Revert -Snapshot $checkpoint
    # A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
    # Revert restores exactly that - so the VM is Suspended here, not Running as it was before the
    # checkpoint, with a suspend_VDI holding the checkpoint's memory image. Resume clears that:
    # destroying a Suspended VM directly (as a bare "if Running: HardShutdown" check would, since the
    # VM is never Running here) leaves that suspend_VDI behind as a storage leak.
    Write-Host "Reverted the VM to the checkpoint; power state now: $((Get-XenVM -Ref $ref).power_state)"
    $vm | Invoke-XenVM -XenAction Resume

    # Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
    Remove-VmAndDisks -Ref $checkpoint.opaque_ref
    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $ref
    Write-Host "OK: checkpoint-vm"
    $session | Disconnect-XenServer
}
