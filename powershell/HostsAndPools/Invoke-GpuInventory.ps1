function Invoke-GpuInventory {
    <#
    .SYNOPSIS
        GPU inventory.
    .DESCRIPTION
        Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.
    .EXAMPLE
        Invoke-GpuInventory -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $groups = Get-XenGPUGroup
    Write-Host "GPU groups ($(@($groups).Count)):"
    foreach ($group in $groups) {
        $types = $group.supported_VGPU_types | ForEach-Object { (Get-XenVGPUType -Ref $_).model_name }
        Write-Host "  - $($group.name_label): $(@($group.PGPUs).Count) pGPU(s), vGPU types: $($types -join ', ')"
    }
    # How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU full
    # before using the next, breadth-first spreads them out.
    $group = $groups | Select-Object -First 1
    $before = $group.allocation_algorithm
    $group | Set-XenGPUGroup -AllocationAlgorithm breadth_first
    $after = (Get-XenGPUGroup -Ref $group.opaque_ref).allocation_algorithm
    Write-Host "Allocation:      $before -> $after"
    $group | Set-XenGPUGroup -AllocationAlgorithm $before
    Write-Host "OK: gpu-inventory"
    $session | Disconnect-XenServer
}
