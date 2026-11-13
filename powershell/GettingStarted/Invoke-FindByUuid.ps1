function Invoke-FindByUuid {
    <#
    .SYNOPSIS
        Look up an object by UUID.
    .DESCRIPTION
        Resolve a stable UUID back to a live object reference — how to persist a reference to an object
        across sessions.
    .EXAMPLE
        Invoke-FindByUuid -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # UUIDs are stable identifiers you can persist and resolve back to a (session-scoped) ref.
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $uuid = $vm.uuid

    $resolved = Get-XenVM -Uuid $uuid
    Write-Host "UUID $uuid resolves to $($resolved.name_label)"
    Write-Host "Same object: $($resolved.uuid -eq $vm.uuid)"
    Write-Host "OK: find-by-uuid"
    $session | Disconnect-XenServer
}
