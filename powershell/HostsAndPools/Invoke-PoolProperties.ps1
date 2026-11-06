function Invoke-PoolProperties {
    <#
    .SYNOPSIS
        Pool properties.
    .DESCRIPTION
        Read the pool name and default storage repository, then rename the pool and restore it.
    .EXAMPLE
        Invoke-PoolProperties -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    $original = $pool.name_label
    $defaultSr = $pool.default_SR
    $srName = if ($defaultSr -eq "OpaqueRef:NULL") { "(none)" } else { (Get-XenSR -Ref $defaultSr).name_label }
    Write-Host "Pool:       '$original'"
    Write-Host "Default SR: $srName"

    $pool | Set-XenPool -NameLabel "sdk-pool-renamed"
    Write-Host "Renamed to: '$((Get-XenPool -Ref $pool).name_label)'"

    $pool | Set-XenPool -NameLabel $original  # restore
    Write-Host "OK: pool-properties"
    $session | Disconnect-XenServer
}
