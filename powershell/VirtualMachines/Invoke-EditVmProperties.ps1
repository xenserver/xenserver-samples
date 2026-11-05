function Invoke-EditVmProperties {
    <#
    .SYNOPSIS
        Edit VM properties.
    .DESCRIPTION
        Change a VM's description and custom metadata, then read the changes back.
    .EXAMPLE
        Invoke-EditVmProperties -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $originalDesc = $vm.name_description

    # Set-XenVM -OtherConfig replaces the whole map, so copy the current one, add our entry and write it
    # back (leaving the VM's existing keys intact).
    $current = $vm.other_config
    $oc = @{}
    foreach ($k in $current.Keys) { $oc[$k] = $current[$k] }
    $oc["sdk_example"] = "true"
    $vm | Set-XenVM -NameDescription "Edited by the SDK example"
    $vm | Set-XenVM -OtherConfig $oc

    $edited = Get-XenVM -Ref $vm.opaque_ref
    Write-Host "New description: $($edited.name_description)"
    Write-Host "other_config[sdk_example] = $($edited.other_config['sdk_example'])"

    # Put it back so the example is repeatable: restore the description and drop the key we added.
    $vm | Set-XenVM -NameDescription $originalDesc
    $vm | Remove-XenVMProperty -OtherConfig "sdk_example"
    Write-Host "OK: edit-vm-properties"
    $session | Disconnect-XenServer
}
