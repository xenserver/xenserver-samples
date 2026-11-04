function Invoke-NewVmWizard {
    <#
    .SYNOPSIS
        Create a VM (full workflow).
    .DESCRIPTION
        Create a VM end to end: pick a template, name the VM, choose an installation source and a home
        server, set CPU & memory, add a disk on a storage repository, attach a network interface and start
        it — the full sequence, rather than a single clone call.
    .EXAMPLE
        Invoke-NewVmWizard -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "wizard-vm"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Page 1 - Template.
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    Write-Host "Template:      $($template.name_label)"

    # Page 2 - Name and description.
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    $ref = $vm.opaque_ref
    $vm | Set-XenVM -NameDescription "Created by the full New VM wizard example"
    $vm | Set-XenVM -IsATemplate $false
    Write-Host "Created VM:    $((Get-XenVM -Ref $ref).uuid)"

    # Page 3 - Installation media (a network install repository). Set replaces other_config wholesale,
    # so merge our key into a copy of the current map.
    $current = (Get-XenVM -Ref $ref).other_config
    $oc = @{}
    foreach ($k in $current.Keys) { $oc[$k] = $current[$k] }
    $oc["install-repository"] = "http://mirror.example.com/rocky/9/os/x86_64"
    $vm | Set-XenVM -OtherConfig $oc
    Write-Host "Install media: network repository"

    # Page 4 - Home server (affinity).
    $xenHost = Get-XenHost | Select-Object -First 1
    $vm | Set-XenVM -Affinity $xenHost
    Write-Host "Home server:   $($xenHost.name_label)"

    # Page 5 - CPU & Memory. -MemoryLimits takes [static_min, static_max, dynamic_min, dynamic_max].
    $vm | Set-XenVM -VCPUsMax 2 -VCPUsAtStartup 2
    $vm | Set-XenVM -MemoryLimits (512MB, 2GB, 2GB, 2GB)
    Write-Host "CPU/memory:    2 vCPUs, 2 GiB"

    # Page 6 - Storage: add a disk on a (non-ISO) SR.
    $sr = Get-XenSR | Where-Object { $_.content_type -ne 'iso' -and $_.type -notin @('iso', 'udev') } | Select-Object -First 1
    $vbdDevice = (Get-XenVMProperty -Ref $ref -XenProperty AllowedVBDDevices)[0]
    $vdi = New-XenVDI -NameLabel "$NewVmName disk 0" -NameDescription "System disk created by the wizard example" `
        -SR $sr -VirtualSize 24GB -Type system -Sharable $false -ReadOnly $false -PassThru
    New-XenVBD -VM (Get-XenVM -Ref $ref) -VDI $vdi -Userdevice $vbdDevice -Bootable $true `
        -Mode RW -Type Disk -Empty $false | Out-Null
    Write-Host "Storage:       24 GiB disk on $($sr.name_label)"

    # Page 7 - Networking: attach a VIF to a network.
    $net = Get-XenNetwork | Select-Object -First 1
    $vifDevice = (Get-XenVMProperty -Ref $ref -XenProperty AllowedVIFDevices)[0]
    New-XenVIF -VM (Get-XenVM -Ref $ref) -Network $net -Device $vifDevice -MAC "" -MTU 1500 | Out-Null
    Write-Host "Networking:    NIC on $($net.name_label)"

    # Page 8 - Finish: start the VM.
    $vm | Invoke-XenVM -XenAction Start

    $started = Get-XenVM -Ref $ref
    Write-Host "--- Result ---"
    Write-Host "power state:   $($started.power_state)"
    Write-Host "vCPUs:         $($started.VCPUs_max)"
    Write-Host "disks:         $(@($started.VBDs).Count), NICs: $(@($started.VIFs).Count)"

    # Tidy up so the example is repeatable.
    $vm | Invoke-XenVM -XenAction HardShutdown
    $vm | Remove-XenVM
    $vdi | Remove-XenVDI
    Write-Host "OK: new-vm-wizard"
    $session | Disconnect-XenServer
}
