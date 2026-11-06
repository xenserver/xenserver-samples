function Invoke-CreateNfsSr {
    <#
    .SYNOPSIS
        Create an NFS SR.
    .DESCRIPTION
        Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and
        forget it.
    .EXAMPLE
        Invoke-CreateNfsSr -Url https://xenserver -UserName root -Password $password -NfsServer 192.0.2.10 -NfsPath /export/sdk
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$NfsServer,
        [Parameter(Mandatory = $true)][string]$NfsPath,
        [string]$SrName = "sdk-example-nfs"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $deviceConfig = @{ server = $NfsServer; serverpath = $NfsPath; nfsversion = "3" }

    $sr = New-XenSR -XenHost $xenHost -DeviceConfig $deviceConfig -PhysicalSize 0 `
        -NameLabel $SrName -NameDescription "NFS SR created by the SDK example" `
        -Type "nfs" -ContentType "user" -Shared $true -PassThru
    Write-Host "Created SR: $($sr.uuid)"

    Invoke-DetachAndForgetSr -Ref $sr
    Write-Host "OK: create-nfs-sr"
    $session | Disconnect-XenServer
}
