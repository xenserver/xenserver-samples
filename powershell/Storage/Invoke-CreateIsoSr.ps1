function Invoke-CreateIsoSr {
    <#
    .SYNOPSIS
        Create an ISO library SR.
    .DESCRIPTION
        Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so the
        images are available as installation media.

        Connect an ISO-library SR to a file share of ISO images (here an NFS export, Location
        "server:/path").
    .EXAMPLE
        Invoke-CreateIsoSr -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Location
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $deviceConfig = @{ location = $Location; type = "nfs_iso" }
    $sr = New-XenSR -XenHost $xenHost -DeviceConfig $deviceConfig -PhysicalSize 0 `
        -NameLabel "sdk-example-iso" -NameDescription "ISO library created by the SDK example" `
        -Type "iso" -ContentType "iso" -Shared $true -PassThru
    Write-Host "Created ISO SR: $($sr.uuid)"
    Invoke-DetachAndForgetSr -Ref $sr
    Write-Host "OK: create-iso-sr"
    $session | Disconnect-XenServer
}
