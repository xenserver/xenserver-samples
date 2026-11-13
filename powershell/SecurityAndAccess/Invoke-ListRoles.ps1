function Invoke-ListRoles {
    <#
    .SYNOPSIS
        List RBAC roles.
    .DESCRIPTION
        Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to
        users.
    .EXAMPLE
        Invoke-ListRoles -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # RBAC subjects map to these roles. Role records include every permission too; the roles a user
    # can be granted are the ones made of permissions (non-empty subroles), as xe role-list shows.
    $roles = Get-XenRole | Where-Object { $_.subroles.Count -gt 0 } |
        Select-Object -ExpandProperty name_label -Unique | Sort-Object
    Write-Host "Roles ($(@($roles).Count)): $(($roles | Select-Object -First 8) -join ', ')"
    Write-Host "OK: list-roles"
    $session | Disconnect-XenServer
}
