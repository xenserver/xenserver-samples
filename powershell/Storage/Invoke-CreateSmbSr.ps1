function Invoke-CreateSmbSr {
    <#
    .SYNOPSIS
        Create an SMB SR.
    .DESCRIPTION
        Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
        credentials (the password as a secret, never in plain text).
    .EXAMPLE
        Invoke-CreateSmbSr -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Share,
        [Parameter(Mandatory = $true)][string]$SmbUsername,
        [Parameter(Mandatory = $true)][string]$SmbPassword,
        [string]$SrName = "sdk-example-smb"
    )
    # Connect a shared SR to an SMB/CIFS file share (create validates + sizes from the share).
    #
    # The password travels as a Secret, not plaintext device-config.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1

    $secret = New-XenSecret -Value $SmbPassword -OtherConfig @{} -PassThru
    $deviceConfig = @{
        # server is the share as one UNC path, //server/share: the SMB driver has no separate serverpath.
        server          = "//$Server$Share"
        username        = $SmbUsername
        password_secret = $secret.uuid
    }
    $sr = New-XenSR -XenHost $xenHost -DeviceConfig $deviceConfig -PhysicalSize 0 `
        -NameLabel $SrName -NameDescription "SMB SR created by the SDK example" `
        -Type "smb" -ContentType "user" -Shared $true -PassThru
    Write-Host "Created SR: $($sr.uuid) ($([math]::Floor([long]($sr.physical_size) / 1GB)) GiB)"
    Invoke-DetachAndForgetSr -Ref $sr.opaque_ref
    Remove-XenSecret -Ref $secret.opaque_ref
    Write-Host "OK: create-smb-sr"
    $session | Disconnect-XenServer
}
