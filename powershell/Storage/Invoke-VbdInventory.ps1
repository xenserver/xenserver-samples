function Invoke-VbdInventory {
    <#
    .SYNOPSIS
        Inventory a VM's disks.
    .DESCRIPTION
        List a VM's attached disks and the size of each.
    .EXAMPLE
        Invoke-VbdInventory -Url https://xenserver -UserName root -Password $password -VmName 'db-01'
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
    Write-Host "Disks of '$($vm.name_label)':"
    (Get-XenVM -Ref $vm).VBDs |
        ForEach-Object { Get-XenVBD -Ref $_ } |
        Where-Object { $_.type -eq 'Disk' } |
        ForEach-Object {
            $vdiRef = $_.VDI
            $size = if ($vdiRef -eq 'OpaqueRef:NULL') { 0 } else { [long]((Get-XenVDI -Ref $vdiRef).virtual_size / 1GB) }
            Write-Host "  - device $($_.userdevice): $size GiB"
        }
    Write-Host "OK: vbd-inventory"
    $session | Disconnect-XenServer
}
