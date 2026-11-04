function Invoke-CustomFields {
    <#
    .SYNOPSIS
        Custom fields.
    .DESCRIPTION
        Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the
        object.
    .EXAMPLE
        Invoke-CustomFields -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # XenCenter's custom fields are stored in other_config under "XenCenter.CustomFields.<name>".
    # Set-XenVM -OtherConfig replaces the whole map, so merge the field into a copy; Remove-XenVMProperty
    # -OtherConfig then drops it again by key.
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $key = "XenCenter.CustomFields.Owner"

    $current = $vm.other_config
    $oc = @{}
    foreach ($k in $current.Keys) { $oc[$k] = $current[$k] }
    $oc[$key] = "Platform Team"
    $vm | Set-XenVM -OtherConfig $oc
    Write-Host "Custom field Owner = $((Get-XenVM -Ref $vm.opaque_ref).other_config[$key])"

    $vm | Remove-XenVMProperty -OtherConfig $key
    Write-Host "OK: custom-fields"
    $session | Disconnect-XenServer
}
