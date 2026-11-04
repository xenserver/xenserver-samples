function Invoke-ManageVif {
    <#
    .SYNOPSIS
        Manage network interfaces.
    .DESCRIPTION
        Attach a virtual network interface to a VM and remove it again.
    .EXAMPLE
        Invoke-ManageVif -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-vif"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm.opaque_ref
    $ref = $vm.opaque_ref

    $net = Get-XenNetwork | Select-Object -First 1
    $device = (Get-XenVMProperty -Ref $ref -XenProperty AllowedVIFDevices)[0]

    $vif = New-XenVIF -VM (Get-XenVM -Ref $ref) -Network $net -Device $device -MAC "" -MTU 1500 -PassThru
    Write-Host "Attached a VIF on device $device; VM now has $(@((Get-XenVM -Ref $ref).VIFs).Count) NIC(s)"

    $vif | Remove-XenVIF
    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "OK: manage-vif"
    $session | Disconnect-XenServer
}
