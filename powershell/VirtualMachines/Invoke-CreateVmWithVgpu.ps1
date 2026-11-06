function Invoke-CreateVmWithVgpu {
    <#
    .SYNOPSIS
        Create a VM with a vGPU.
    .DESCRIPTION
        Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU
        type, attach it, and read the assignment back.
    .EXAMPLE
        Invoke-CreateVmWithVgpu -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-vgpu-vm"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Find a GPU group that offers a real (non-passthrough) vGPU type, plus that type.
    $group = $null; $vgpuType = $null
    foreach ($g in Get-XenGPUGroup) {
        if (-not $g.PGPUs) { continue }
        foreach ($tRef in $g.supported_VGPU_types) {
            $t = Get-XenVGPUType -Ref $tRef
            if ($t.model_name -ne 'passthrough') { $group = $g; $vgpuType = $t; break }
        }
        if ($vgpuType) { break }
    }
    if (-not $vgpuType) { throw "No GPU group offers a vGPU type." }
    Write-Host "Using vGPU type: $($vgpuType.model_name) ($([int]($vgpuType.framebuffer_size / 1MB)) MB framebuffer)"

    # Provision a fresh VM from the template to attach the vGPU to.
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm

    # Assign the vGPU: device "0" is the VM's first vGPU slot, other_config is empty.
    $vgpu = New-XenVGPU -VM $vm -GPUGroup $group -Device "0" -OtherConfig @{} -Type $vgpuType -PassThru
    Write-Host "Created vGPU: $($vgpu.uuid)"

    # Read the assignment back.
    $assignedVm = Get-XenVM -Ref $vm
    $assigned = (Get-XenVGPUType -Ref (Get-XenVGPU -Ref $assignedVm.VGPUs[0]).type).model_name
    Write-Host "VM now has $($assignedVm.VGPUs.Count) vGPU(s); type = $assigned"

    # Tidy up so the example is repeatable.
    $vgpu | Remove-XenVGPU
    Remove-VmAndDisks -Ref $vm
    Write-Host "Cleaned up the example VM and its vGPU."

    Write-Host "OK: create-vm-with-vgpu"
    $session | Disconnect-XenServer
}
