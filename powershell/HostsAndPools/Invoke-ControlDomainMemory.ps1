function Invoke-ControlDomainMemory {
    <#
    .SYNOPSIS
        Change control domain memory.
    .DESCRIPTION
        Read and change a host's control domain (dom0) memory, then put it back. One setter pins the static
        and dynamic bounds together, because dom0 does not balloon.
    .EXAMPLE
        Invoke-ControlDomainMemory -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $xenHost = Get-XenHost | Select-Object -First 1
    # dom0 is a VM like any other, found among the host's resident VMs.
    $dom0 = $xenHost.resident_VMs | ForEach-Object { Get-XenVM -Ref $_.opaque_ref } |
        Where-Object { $_.is_control_domain } | Select-Object -First 1
    $original = [long]$dom0.memory_dynamic_min
    Write-Host ("$($xenHost.name_label) dom0: {0:N1} GiB" -f ($original / 1GB))

    # -Memory, not -MemoryDynamicRange: dom0 does not balloon, so this one setter pins the static and
    # dynamic bounds and the target together. The new size takes effect at the next reboot, which is why XenCenter offers
    # this only in maintenance mode — the API itself does not stop you.
    Set-XenVM -VM $dom0 -Memory ($original + 1GB)
    $updated = Get-XenVM -Ref $dom0.opaque_ref
    Write-Host ("  now {0:N1} GiB (static {1}-{2}, dynamic {3}-{4})" -f
        ($updated.memory_dynamic_min / 1GB), $updated.memory_static_min, $updated.memory_static_max,
        $updated.memory_dynamic_min, $updated.memory_dynamic_max)

    Set-XenVM -VM $dom0 -Memory $original   # leave the pool as we found it
    Write-Host "OK: control-domain-memory"
    $session | Disconnect-XenServer
}
