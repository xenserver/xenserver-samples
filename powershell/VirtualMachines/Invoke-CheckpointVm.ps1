function Invoke-CheckpointVm {
    <#
    .SYNOPSIS
        Checkpoint & revert.
    .DESCRIPTION
        Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
        you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must
        have a guest OS with PV drivers (vm_name).
    .EXAMPLE
        Invoke-CheckpointVm -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
    # Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest freezes
    # its processes and suspends itself. A guest that is still booting can fail to freeze a process that is
    # busy starting up, and it then abandons the suspend without telling the host, which waits until
    # VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here.
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    if ($vm.power_state -ne 'Running') { throw "$VmName must be running to be checkpointed" }
    $ref = $vm.opaque_ref

    $checkpoint = $vm | Invoke-XenVM -XenAction Checkpoint -NewName "sdk-example-checkpoint-1" -PassThru
    Write-Host "Created checkpoint: $($checkpoint.uuid)"
    Write-Host "is_a_snapshot = $($checkpoint.is_a_snapshot)"

    $vm | Invoke-XenVM -XenAction Revert -Snapshot $checkpoint
    # A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
    # Revert restores exactly that - so the VM is Suspended here, not Running as it was before the
    # checkpoint, with a suspend_VDI holding the checkpoint's memory image. Resume picks up from there
    # (and frees that memory image).
    Write-Host "Reverted $VmName to the checkpoint; power state now: $((Get-XenVM -Ref $ref).power_state)"
    $vm | Invoke-XenVM -XenAction Resume
    Write-Host "Resumed $VmName; power state now: $((Get-XenVM -Ref $ref).power_state)"

    # Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
    Remove-VmAndDisks -Ref $checkpoint
    Write-Host "Deleted the checkpoint."
    Write-Host "OK: checkpoint-vm"
    $session | Disconnect-XenServer
}
