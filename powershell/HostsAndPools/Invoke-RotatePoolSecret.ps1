function Invoke-RotatePoolSecret {
    <#
    .SYNOPSIS
        Rotate the pool secret.
    .DESCRIPTION
        Rotate the shared secret that authenticates pool members to each other.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    Write-Host "Pool:           $($pool.name_label)"

    # xapi checks its own preconditions before rotating - HA must be disabled, every host must be live,
    # no rolling pool upgrade may be in progress, and the pool must be licensed for it - and raises a
    # clear error naming which one failed rather than silently refusing. Report that explanation instead
    # of letting an unhandled failure speak for itself.
    $explanations = @{
        "HA_IS_ENABLED"                 = "HA is enabled on this pool; disable it first."
        "CANNOT_CONTACT_HOST"           = "a host in the pool is not reachable."
        "NOT_SUPPORTED_DURING_UPGRADE"  = "a rolling pool upgrade is in progress."
        "LICENCE_RESTRICTION"           = "this edition is not licensed for pool secret rotation."
    }
    try {
        # A pool-wide operation; existing sessions survive it.
        Invoke-XenPool -Ref $pool.opaque_ref -XenAction RotateSecret
        Write-Host "Rotated. Still connected: $(@(Get-XenPool).Count -eq 1)"
    }
    catch {
        $ex = $_.Exception
        while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
        $code = if ($ex -and $ex.ErrorDescription) { $ex.ErrorDescription[0] } else { $_.Exception.Message }
        $explanation = if ($explanations.ContainsKey($code)) { $explanations[$code] } else { "see the error for detail" }
        Write-Host "Could not rotate the pool secret: $code ($explanation)"
    }
    Write-Host "OK: rotate-pool-secret"
    Disconnect-XenServer -Session $session
}
