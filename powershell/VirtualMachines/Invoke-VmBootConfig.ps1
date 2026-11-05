function Invoke-VmBootConfig {
    <#
    .SYNOPSIS
        VM boot configuration.
    .DESCRIPTION
        Set a VM's vCPU counts and boot order, then read them back.
    .EXAMPLE
        Invoke-VmBootConfig -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-boot"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm.opaque_ref
    $ref = $vm.opaque_ref

    # Set the vCPU topology and switch the VM to UEFI boot: firmware ("bios"/"uefi") lives in
    # HVM_boot_params, Secure Boot in platform["secureboot"]. "auto" (not a hard-coded "true") is the xe
    # convention: xapi resolves it against whether the pool actually holds Secure Boot certificates, at
    # VM.start time - a hard "true" would claim Secure Boot is on even on a template that was never set up for
    # it, since Set-XenVM does no validation of its own.
    $vm | Set-XenVM -VCPUsMax 4 -VCPUsAtStartup 2 -HVMBootParams @{ order = "cdn"; firmware = "uefi" }
    $platform = (Get-XenVM -Ref $ref).platform
    $platform["secureboot"] = "auto"
    $vm | Set-XenVM -Platform $platform

    $configured = Get-XenVM -Ref $ref
    Write-Host "vCPUs: $($configured.VCPUs_at_startup)/$($configured.VCPUs_max)"
    Write-Host "Boot order: $($configured.HVM_boot_params['order'])"
    Write-Host "Boot mode: firmware=$($configured.HVM_boot_params['firmware']), secureboot=$($configured.platform['secureboot']) (resolved against pool certificates at boot)"

    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "OK: vm-boot-config"
    $session | Disconnect-XenServer
}
