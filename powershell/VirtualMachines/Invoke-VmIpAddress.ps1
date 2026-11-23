function Invoke-VmIpAddress {
    <#
    .SYNOPSIS
        Get a VM's IP address.
    .DESCRIPTION
        Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.
    .EXAMPLE
        Invoke-VmIpAddress -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = 'web-01',
        [int]$TimeoutSeconds = 60,
        [int]$IntervalSeconds = 2
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    # A VM that has only just started may not have reported in yet (no guest_metrics at all, or an empty
    # networks map) - retry for a while before concluding it has no guest agent reporting.
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $ip = $null
    while ($true) {
        # An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
        $current = Get-XenVM -Ref $vm.opaque_ref
        $ip = $null
        if ($current.power_state -eq 'Running' -and $current.guest_metrics -ne 'OpaqueRef:NULL') {
            $networks = (Get-XenVMGuestMetrics -Ref $current.guest_metrics).networks
            if ($networks.ContainsKey("0/ip") -and $networks["0/ip"]) {
                $ip = $networks["0/ip"]
            }
        }
        if ($ip -or (Get-Date) -gt $deadline) { break }
        Start-Sleep -Seconds $IntervalSeconds
    }
    if ($ip) {
        Write-Host "  $($VmName): $ip"
    } else {
        Write-Host "  $($VmName): no IP address reported yet (no guest agent running?)"
    }
    Write-Host "OK: vm-ip-address"
    $session | Disconnect-XenServer
}
