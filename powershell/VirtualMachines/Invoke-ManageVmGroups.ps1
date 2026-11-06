function Invoke-ManageVmGroups {
    <#
    .SYNOPSIS
        Manage VM groups.
    .DESCRIPTION
        Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then
        take the VM out again and delete the group.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName,
        [string]$GroupName = "sdk-example-group"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }

    # anti_affinity asks the pool to keep the group's members on different hosts.
    $group = New-XenVMGroup -NameLabel $GroupName `
        -NameDescription 'Anti-affinity group created by the SDK example' `
        -Placement anti_affinity -PassThru
    Write-Host "Created group:  $($group.uuid)"

    # Membership is written from the VM side...
    Set-XenVM -VM $vm -Groups @($group)

    # ...and read back from the group side, which is the half that is easy to get wrong.
    $members = (Get-XenVMGroup -Ref $group).VMs
    Write-Host "Group members:  $($members.Count)"
    foreach ($m in $members) { Write-Host "  $((Get-XenVM -Ref $m).name_label)" }

    # VM_group.destroy already clears the group from every member VM's groups field - no need to remove
    # membership ourselves first.
    Remove-XenVMGroup -Ref $group
    Write-Host "OK: manage-vm-groups"
    Disconnect-XenServer -Session $session
}
