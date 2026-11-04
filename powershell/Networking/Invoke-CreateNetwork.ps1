function Invoke-CreateNetwork {
    <#
    .SYNOPSIS
        Create a network.
    .DESCRIPTION
        Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to
        each other privately.
    .EXAMPLE
        Invoke-CreateNetwork -Url https://xenserver -UserName root -Password $password -NetworkName 'sdk-example-net'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$NetworkName = "sdk-example-net"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $net = New-XenNetwork -NameLabel $NetworkName `
        -NameDescription "Internal network created by the SDK example" -MTU 1500 -PassThru
    Write-Host "Created network: $($net.uuid)"

    # Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this is a
    # property of the network rather than of any one interface on it.
    $net | Set-XenNetwork -MTU 9000
    Write-Host "MTU now:         $((Get-XenNetwork -Ref $net.opaque_ref).MTU)"

    $net | Remove-XenNetwork
    Write-Host "OK: create-network"
    $session | Disconnect-XenServer
}
