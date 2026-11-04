function Invoke-DeleteVm {
    <#
    .SYNOPSIS
        Delete a VM.
    .DESCRIPTION
        Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are destroyed
        explicitly afterward.
    .EXAMPLE
        Invoke-DeleteVm -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-delete"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Make a throwaway VM to delete. Remove-XenVM removes the VM but leaves its disks, so the owned
    # VDIs are destroyed explicitly afterward - exactly what XenCenter's Delete VM does.
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm.opaque_ref
    $uuid = (Get-XenVM -Ref $vm.opaque_ref).uuid

    $vdis = (Get-XenVM -Ref $vm.opaque_ref).VBDs |
        ForEach-Object { Get-XenVBD -Ref $_.opaque_ref } |
        Where-Object { $_.type -eq 'Disk' } |
        ForEach-Object { $_.VDI.opaque_ref }
    Write-Host "Deleting VM $uuid with $(@($vdis).Count) disk(s)"

    $vm | Remove-XenVM
    $vdis | ForEach-Object { Remove-XenVDI -Ref $_ }

    $stillThere = [bool](Get-XenVM | Where-Object { $_.uuid -eq $uuid })
    Write-Host "VM still present: $stillThere"
    Write-Host "OK: delete-vm"
    $session | Disconnect-XenServer
}
