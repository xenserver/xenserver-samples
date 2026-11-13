function Invoke-ConfigureUpdates {
    <#
    .SYNOPSIS
        Configure updates (CDN).
    .DESCRIPTION
        Point the pool at a CDN update repository and turn on automatic update sync: register a repository,
        set it as the pool's repository, enable update sync, read it back, then tidy up.
    .EXAMPLE
        Invoke-ConfigureUpdates -Url https://xenserver -UserName root -Password $password `
    .EXAMPLE
        -RepoUrl https://repo.ops.xenserver.com/xs9 -SourceUrl https://repo-src.ops.xenserver.com/xs9
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $repos = @(New-UpdateRepositories -Session $session -RepoUrl $RepoUrl -SourceUrl $SourceUrl)
    Write-Host "Introduced repositories: $(($repos | ForEach-Object { $_.name_label }) -join ', ')"

    $pool = Get-XenPool | Select-Object -First 1
    # Remember the pool's own repositories, to put them back afterwards.
    $previous = @((Get-XenPool -Ref $pool).repositories)
    $pool | Set-XenPool -Repositories $repos
    $pool | Set-XenPool -UpdateSyncEnabled $true
    $p = Get-XenPool -Ref $pool
    Write-Host "Pool repositories: $($p.repositories.Count); auto-sync enabled: $($p.update_sync_enabled)"

    # Tidy up so the example is repeatable.
    $pool | Set-XenPool -UpdateSyncEnabled $false
    $pool | Set-XenPool -Repositories $previous
    $repos | ForEach-Object { $_ | Invoke-XenRepository -XenAction Forget }
    Write-Host "OK: configure-updates"
    $session | Disconnect-XenServer
}
