function Invoke-ListNetworks {
    <#
    .SYNOPSIS
        List networks.
    .DESCRIPTION
        Enumerate the pool's networks with their physical and virtual interface counts.
    .EXAMPLE
        Invoke-ListNetworks -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $nets = Get-XenNetwork | Sort-Object name_label
    Write-Host "Networks ($(@($nets).Count)):"
    $nets | ForEach-Object {
        Write-Host "  - $($_.name_label): $(@($_.PIFs).Count) PIF(s), $(@($_.VIFs).Count) VIF(s)"
    }
    Write-Host "OK: list-networks"
    $session | Disconnect-XenServer
}
