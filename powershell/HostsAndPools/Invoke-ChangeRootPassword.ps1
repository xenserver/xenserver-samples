function Invoke-ChangeRootPassword {
    <#
    .SYNOPSIS
        Change the root password.
    .DESCRIPTION
        Change the local superuser password, then change it back.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $randomBytes = [byte[]]::new(18)
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($randomBytes)
    $temporary = [Convert]::ToBase64String($randomBytes).Replace('+', '-').Replace('/', '_').TrimEnd('=')

    # The module ships no cmdlet for session.change_password, so this is the one place these examples
    # call the binding directly. The session Connect-XenServer hands back IS a XenAPI.Session, which is
    # exactly what the static wants. Note it takes the OLD password as well as the new one, even though
    # you are already authenticated.
    [XenAPI.Session]::change_password($session, $Password, $temporary)
    Write-Host "Password changed."
    try {
        # The existing session stays valid afterwards - only NEW connections need the new password, so a
        # script can carry on without reconnecting.
        Write-Host "Session still usable: $(@(Get-XenPool).Count -eq 1)"

        # change_password on a ROOT session ignores the old password entirely (see xapi's
        # xapi_session.ml) - the call succeeds regardless of what is passed as the old password, so there is
        # no wrong-old-password failure to demonstrate here. The real gate is who may call this at all: only
        # a session with is_local_superuser may.
        Write-Host "is_local_superuser: $($session.IsLocalSuperuser)"
    } finally {
        # Put the original password back however the above went, so a failure part-way through doesn't
        # leave root on the temporary one.
        [XenAPI.Session]::change_password($session, $temporary, $Password)
    }
    Write-Host "Password restored."
    Write-Host "OK: change-root-password"
    Disconnect-XenServer -Session $session
}
