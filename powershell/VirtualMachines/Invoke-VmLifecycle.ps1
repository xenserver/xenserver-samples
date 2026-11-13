function Invoke-VmLifecycle {
    <#
    .SYNOPSIS
        VM power lifecycle.
    .DESCRIPTION
        Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down
        cleanly. Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy
        of a VM with a guest OS and PV drivers (source_vm), which is deleted again with its disks
        afterwards.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [string]$NewVmName = "sdk-example-lifecycle"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so
    # the copy is made from SourceVm, a VM with a guest OS and PV drivers, and the example waits for the
    # guest to report in after starting. Suspend also needs a suspend-image SR (the VM's own, else the
    # pool's, else the host's); check one is actually configured before trying.
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm

    function State { (Get-XenVM -Ref $ref).power_state }

    Write-Host "Initial power state: $(State)"

    # Start asynchronously: -Async -PassThru emits a Task, which pipes straight into Wait-XenTask.
    # -ShowProgress surfaces the task's progress - the idiom for long-running operations where you want
    # to track progress rather than block silently.
    $vm | Invoke-XenVM -XenAction Start -Async -PassThru | Wait-XenTask -ShowProgress
    Wait-GuestAgent -Ref $ref
    Write-Host "After start:    $(State)"

    # The emulated hardware (the device model) can be restarted under a running guest without rebooting
    # it - what you reach for when the VM's virtual devices misbehave.
    $vm | Invoke-XenVM -XenAction RestartDeviceModels
    Write-Host "Device models restarted; still $(State)"

    # VM.suspend needs a suspend-image SR actually configured (the VM's own, else the pool's, else the
    # resident host's - the same fallback order xapi's choose_suspend_sr uses) - VM_NO_SUSPEND_SR
    # otherwise. Check before trying rather than assuming one is set.
    if (Test-HasSuspendSr -Vm (Get-XenVM -Ref $ref)) {
        $vm | Invoke-XenVM -XenAction Suspend
        Write-Host "After suspend:  $(State)"
        $vm | Invoke-XenVM -XenAction Resume
        Wait-GuestAgent -Ref $ref   # the PV drivers reconnect after a resume
        Write-Host "After resume:   $(State)"
    }
    else {
        Write-Host "Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host"
    }

    # A clean shutdown asks the guest OS to shut itself down, as pressing the power button would.
    $vm | Invoke-XenVM -XenAction CleanShutdown
    Write-Host "After shutdown: $(State)"

    Remove-VmAndDisks -Ref $ref
    Write-Host "OK: vm-lifecycle"
    $session | Disconnect-XenServer
}

function Test-HasSuspendSr {
    <#
    .SYNOPSIS
        Whether VM.suspend has a suspend-image SR to use.
    .DESCRIPTION
        The VM's own, else the pool's, else the resident host's - the same fallback order xapi's
        choose_suspend_sr uses.
    #>
    param($Vm)
    if ($Vm.suspend_SR -ne 'OpaqueRef:NULL') { return $true }
    $pool = Get-XenPool | Select-Object -First 1
    if ($pool.suspend_image_SR -ne 'OpaqueRef:NULL') { return $true }
    return (Get-XenHost -Ref $pool.master).suspend_image_sr -ne 'OpaqueRef:NULL'
}
