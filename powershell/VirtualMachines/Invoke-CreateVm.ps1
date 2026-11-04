function Invoke-CreateVm {
    <#
    .SYNOPSIS
        Create a VM from a template.
    .DESCRIPTION
        Clone one of the built-in templates and provision the clone into a real, installable VM.
    .EXAMPLE
        Invoke-CreateVm -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-vm"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    Write-Host "Using template: $($template.name_label)"

    # Pipe the template straight into the Clone action; -PassThru returns the new VM object.
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Write-Host "Cloned new VM: $($vm.uuid)"

    Invoke-VmProvision -Ref $vm.opaque_ref
    Write-Host "Provisioned. is_a_template = $((Get-XenVM -Ref $vm.opaque_ref).is_a_template)"

    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "Cleaned up the example VM."

    Write-Host "OK: create-vm"
    $session | Disconnect-XenServer
}
