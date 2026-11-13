function Invoke-CreateBond {
    <#
    .SYNOPSIS
        Create a NIC bond.
    .DESCRIPTION
        Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond
        back, then dissolve it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1

    # Pick up any NIC racked since the host booted. Cheap, and without it a card added a moment ago is
    # not there to bond. PIF.scan takes a HOST, so Invoke-XenPIF cannot bind it - its parameter sets all
    # name a PIF - and the call goes over JSON-RPC instead. Same escape hatch the event API needs.
    Invoke-XenMethod -Session $session -Method 'PIF.scan' -Params @($xenHost.opaque_ref)

    # Spare NICs only. A bond that includes the management interface moves the management address onto
    # the bond master — on a real host that is how you lose the connection you are working over.
    $spares = Get-XenPIF | Where-Object { $_.host -eq $xenHost -and -not $_.management -and $_.physical } |
        Select-Object -First 2
    if (@($spares).Count -lt 2) {
        throw "$($xenHost.name_label) has $(@($spares).Count) spare NIC(s); a bond needs two that aren't the management interface"
    }
    Write-Host "Bonding:      $(($spares | ForEach-Object { $_.device }) -join ', ')"

    # The bond needs a network to sit on.
    $network = New-XenNetwork -NameLabel 'sdk-example-bond' -NameDescription 'Created by the SDK example' -PassThru

    $bond = New-XenBond -Network $network -Members $spares -MAC '' -Mode balance_slb -PassThru
    $master = Get-XenPIF -Ref $bond.master
    Write-Host "Bond master:  $($master.device)"
    Write-Host "Mode:         $($bond.mode)"

    Remove-XenBond -Ref $bond
    Remove-XenNetwork -Ref $network
    Write-Host "Bonds left:   $(@(Get-XenBond).Count)"
    Write-Host "OK: create-bond"
    $session | Disconnect-XenServer
}
