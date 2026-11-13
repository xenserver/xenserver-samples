function Invoke-PoolTags {
    <#
    .SYNOPSIS
        Tag the pool.
    .DESCRIPTION
        Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and
        hosts.
    .EXAMPLE
        Invoke-PoolTags -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Add-XenPool -Tags appends a tag; the pool's current tags are just its .tags property; and
    # Remove-XenPoolProperty -Tags drops one again.
    $pool = Get-XenPool | Select-Object -First 1
    $pool | Add-XenPool -Tags "sdk-managed"
    Write-Host "Pool tags: $((Get-XenPool -Ref $pool).tags -join ', ')"
    $pool | Remove-XenPoolProperty -Tags "sdk-managed"
    Write-Host "OK: pool-tags"
    $session | Disconnect-XenServer
}
