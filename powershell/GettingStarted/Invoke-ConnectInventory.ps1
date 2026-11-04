function Invoke-ConnectInventory {
    <#
    .SYNOPSIS
        Connect & inventory.
    .DESCRIPTION
        Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual
        machines with their power state. This is the starting point for every session.
    .EXAMPLE
        Invoke-ConnectInventory -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    Write-Host "Connected to pool: $($pool.name_label)"

    $hosts = Get-XenHost
    Write-Host "Hosts ($($hosts.Count)):"
    Get-XenHost | ForEach-Object { Write-Host "  - $($_.name_label) ($($_.address))" }

    $vms = Get-XenVM | Where-Object { -not $_.is_a_template -and -not $_.is_control_domain }
    Write-Host "VMs ($($vms.Count)):"
    $vms | ForEach-Object { Write-Host "  - $($_.name_label) [$($_.power_state)]" }

    Write-Host "OK: connect-inventory"
    $session | Disconnect-XenServer
}
