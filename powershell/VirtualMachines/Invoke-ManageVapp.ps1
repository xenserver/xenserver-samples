function Invoke-ManageVapp {
    <#
    .SYNOPSIS
        Manage a vApp.
    .DESCRIPTION
        Group VMs into an appliance that starts and stops together in a defined order, start and shut it
        down as a unit, then remove it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = "db-01"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName

    $vapp = New-XenVMAppliance -NameLabel "sdk-example-vapp" `
        -NameDescription "Created by the SDK example" -PassThru

    # `order` decides the sequence: ascending to start, descending to shut down. That ordering is the
    # reason to use a vApp rather than selecting several VMs.
    Set-XenVM -VM $vm -Appliance $vapp.opaque_ref
    Set-XenVM -VM $vm -Order 0 -StartDelay 5

    Invoke-XenVMAppliance -VMAppliance $vapp -XenAction Start -Paused $false
    Write-Host "Started:        $((Get-XenVM -Name $VmName).power_state)"

    # Shutdown tries each VM's clean shutdown and falls back to a hard one. CleanShutdown alone fails
    # OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers).
    Invoke-XenVMAppliance -VMAppliance $vapp -XenAction Shutdown
    Write-Host "Shut down:      $((Get-XenVM -Name $VmName).power_state)"

    Set-XenVM -VM (Get-XenVM -Name $VmName) -Appliance "OpaqueRef:NULL"
    Remove-XenVMAppliance -VMAppliance $vapp
    Write-Host "OK: manage-vapp"
    $session | Disconnect-XenServer
}
