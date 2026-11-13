function Invoke-ReadMetrics {
    <#
    .SYNOPSIS
        Read host & VM metrics.
    .DESCRIPTION
        Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
    .EXAMPLE
        Invoke-ReadMetrics -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $hm = Get-XenHostMetrics -Ref $xenHost.metrics
    Write-Host ("Host $($xenHost.name_label): " +
        "$([long]($hm.memory_total / 1MB)) MiB total, " +
        "$([long](($xenHost | Invoke-XenHost -XenAction ComputeFreeMemory -PassThru) / 1MB)) MiB free, " +
        "live = $($hm.live)")

    $vm = Get-XenVM |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and $_.power_state -eq 'Running' } |
        Select-Object -First 1
    $vmm = Get-XenVMMetrics -Ref $vm.metrics
    Write-Host ("VM $($vm.name_label): " +
        "$($vmm.VCPUs_number) vCPU(s), $([long]($vmm.memory_actual / 1MB)) MiB")
    Write-Host "OK: read-metrics"
    $session | Disconnect-XenServer
}
