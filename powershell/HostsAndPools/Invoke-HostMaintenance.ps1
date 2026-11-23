function Invoke-HostMaintenance {
    <#
    .SYNOPSIS
        Enter & exit maintenance mode.
    .DESCRIPTION
        Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running guests
        to another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and PV
        drivers (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation
        something to move.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$SourceVm,
        [Parameter(Mandatory = $true)][string]$SrName,
        [string]$NewVmName = "sdk-example-maint"
    )
    # Evacuation needs somewhere else in the pool that can actually see the VM's disk - a VM whose only
    # disk is on local (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a pool's
    # installation-time default SR is commonly local storage. Put the pinned VM's disk on a shared SR
    # explicitly rather than trusting whatever the pool default happens to be. Evacuation also
    # live-migrates the guest, which needs its cooperation (VM_LACKS_FEATURE without PV drivers), so
    # SourceVm must have a guest OS with PV drivers.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
    $masterRef = (Get-XenPool | Select-Object -First 1).master
    $xenHost = Get-XenHost | Where-Object { $masterRef -ne $_ } | Select-Object -First 1
    Write-Host "Maintenance host: $($xenHost.name_label)"

    # Pin a running VM to that host so evacuation has something to move.
    $sr = Get-XenSR -Name $SrName | Where-Object { $_.shared } | Select-Object -First 1
    if (-not $sr) { throw "No shared SR named '$SrName' was found." }
    $vm = Copy-OfGuest -SourceVmName $SourceVm -NewVmName $NewVmName
    $ref = $vm
    Move-DisksToSr -VmRef $ref -SrRef $sr
    $vm | Set-XenVM -Affinity $xenHost
    $vm | Invoke-XenVM -XenAction Start
    Wait-GuestAgent -Ref $ref
    Write-Host "Guest resident on:$((Get-XenHost -Ref (Get-XenVM -Ref $ref).resident_on).name_label)"

    # Enter maintenance mode: disable the host, then evacuate its guests.
    $xenHost | Invoke-XenHost -XenAction Disable
    Write-Host "After disable:    host.enabled = $((Get-XenHost -Ref $xenHost).enabled)"
    Invoke-Evacuate -XenHost $xenHost
    Write-Host "After evacuate:   guest now on $((Get-XenHost -Ref (Get-XenVM -Ref $ref).resident_on).name_label)"

    # Exit maintenance mode.
    $xenHost | Invoke-XenHost -XenAction Enable
    Write-Host "After enable:     host.enabled = $((Get-XenHost -Ref $xenHost).enabled)"

    # Tidy up so the example is repeatable.
    $vm | Invoke-XenVM -XenAction HardShutdown
    Remove-VmAndDisks -Ref $vm
    Write-Host "OK: host-maintenance"
    $session | Disconnect-XenServer
}
