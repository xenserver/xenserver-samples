function Invoke-ListTemplates {
    <#
    .SYNOPSIS
        List templates.
    .DESCRIPTION
        Enumerate the pool's VM templates, both built-in and custom.
    .EXAMPLE
        Invoke-ListTemplates -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $templates = Get-XenVM | Where-Object { $_.is_a_template } | Sort-Object name_label
    Write-Host "Templates ($(@($templates).Count)):"
    $templates | Select-Object -First 8 | ForEach-Object {
        $suffix = if ($_.other_config.ContainsKey("default_template")) { " [built-in]" } else { "" }
        Write-Host "  - $($_.name_label)$suffix"
    }
    Write-Host "OK: list-templates"
    $session | Disconnect-XenServer
}
