function Invoke-DismissAlerts {
    <#
    .SYNOPSIS
        Raise and dismiss alerts.
    .DESCRIPTION
        List the pool's alerts, then dismiss one — what the Notifications view does.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $messages = @(Get-XenMessage)
    Write-Host "Alerts:         $($messages.Count)"

    if ($messages.Count -eq 0) {
        Write-Host "No alerts to dismiss."
    } else {
        $first = $messages[0]
        Write-Host "Dismissing:     $($first.name) (priority $($first.priority))"
        Remove-XenMessage -Ref $first
        Write-Host "Alerts left:    $(@(Get-XenMessage).Count)"
    }
    Write-Host "OK: dismiss-alerts"
    Disconnect-XenServer -Session $session
}
