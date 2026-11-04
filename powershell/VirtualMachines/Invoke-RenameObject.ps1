function Invoke-RenameObject {
    <#
    .SYNOPSIS
        Rename an object.
    .DESCRIPTION
        Change an object's name and read it back — how any object is renamed.
    .EXAMPLE
        Invoke-RenameObject -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $original = $vm.name_label

    $vm | Set-XenVM -NameLabel "sdk-renamed"
    Write-Host "Renamed '$original' -> '$((Get-XenVM -Ref $vm.opaque_ref).name_label)'"

    $vm | Set-XenVM -NameLabel $original  # restore so the example is repeatable
    Write-Host "OK: rename-object"
    $session | Disconnect-XenServer
}
