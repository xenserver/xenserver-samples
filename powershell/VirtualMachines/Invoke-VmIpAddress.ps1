function Invoke-VmIpAddress {
    <#
    .SYNOPSIS
        Get a VM's IP address.
    .DESCRIPTION
        Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
    .EXAMPLE
        Invoke-VmIpAddress -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [int]$TimeoutSeconds = 60,
        [int]$IntervalSeconds = 2
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # A VM that has only just started may not have reported in yet (no guest_metrics at all, or an empty
    # networks map) - retry for a while rather than giving up on the first look.
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        # A running guest reports its IP in networks, keyed "<vif device>/ip" (e.g. "0/ip"). Not every
        # running VM has one (no guest tools, no NIC, still booting), so look at each until one does.
        $vm = $null
        $ip = $null
        foreach ($candidate in Get-XenVM | Where-Object {
                $_.power_state -eq 'Running' -and -not $_.is_a_template -and -not $_.is_control_domain -and
                $_.guest_metrics -ne 'OpaqueRef:NULL'
            }) {
            $networks = (Get-XenVMGuestMetrics -Ref $candidate.guest_metrics).networks
            if ($networks.ContainsKey("0/ip") -and $networks["0/ip"]) {
                $vm = $candidate
                $ip = $networks["0/ip"]
                break
            }
        }
        if ($ip) {
            Write-Host "  $($vm.name_label): $ip"
            break
        }
        if ((Get-Date) -gt $deadline) {
            throw "no running guest reported an IP address within ${TimeoutSeconds}s"
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
    Write-Host "OK: vm-ip-address"
    $session | Disconnect-XenServer
}
