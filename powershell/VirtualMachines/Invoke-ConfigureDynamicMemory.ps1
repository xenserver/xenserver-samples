function Invoke-ConfigureDynamicMemory {
    <#
    .SYNOPSIS
        Configure dynamic memory.
    .DESCRIPTION
        Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the
        ordering rule the four bounds must obey enforced.
    .EXAMPLE
        Invoke-ConfigureDynamicMemory -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.power_state -eq 'Halted'
    } | Select-Object -First 1
    Write-Host ("{0}: static {1}-{2}, dynamic {3}-{4}" -f $vm.name_label,
        (Format-Gib $vm.memory_static_min), (Format-Gib $vm.memory_static_max),
        (Format-Gib $vm.memory_dynamic_min), (Format-Gib $vm.memory_dynamic_max))

    # Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
    # static maximum for every supported guest (lower can make it unstable), and never below the static
    # floor, which is the least the guest can boot in.
    $floor = [Math]::Max($vm.memory_static_min, [long]($vm.memory_static_max * 3 / 4))
    $ceiling = $vm.memory_static_max
    # MemoryDynamicRange takes the pair as one array argument, so the two bounds are set together and
    # cannot momentarily cross each other.
    Set-XenVM -Ref $vm.opaque_ref -MemoryDynamicRange @($floor, $ceiling)
    $after = Get-XenVM -Ref $vm.opaque_ref
    Write-Host ("  dynamic range now {0}-{1}" -f
        (Format-Gib $after.memory_dynamic_min), (Format-Gib $after.memory_dynamic_max))

    # The ordering is enforced, not advisory: a range wider than the static bounds is refused rather
    # than quietly clamped.
    try {
        # Parentheses are load-bearing: PowerShell's comma operator binds TIGHTER than multiplication, so
        # @($floor, $ceiling * 2) is @($floor, $ceiling) repeated twice - a four-element array whose first
        # two values are the range we already set. The call then succeeds and proves nothing.
        Set-XenVM -Ref $vm.opaque_ref -MemoryDynamicRange @($floor, ($ceiling * 2)) -ErrorAction Stop
        Write-Host "  ERROR: an out-of-range maximum was accepted"
    }
    catch {
        Write-Host "  refused a dynamic_max above static_max: $($_.Exception.Message)"
    }

    Set-XenVM -Ref $vm.opaque_ref -MemoryDynamicRange @($vm.memory_dynamic_min, $vm.memory_dynamic_max)
    Write-Host "OK: configure-dynamic-memory"
    $session | Disconnect-XenServer
}

function Format-Gib {
    param([long]$Bytes)
    "{0:N1} GiB" -f ($Bytes / 1GB)
}
