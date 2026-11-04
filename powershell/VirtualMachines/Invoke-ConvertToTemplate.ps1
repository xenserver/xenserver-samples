function Invoke-ConvertToTemplate {
    <#
    .SYNOPSIS
        Convert a VM to a template.
    .DESCRIPTION
        Turn a VM into a reusable custom template. This is a one-way operation.
    .EXAMPLE
        Invoke-ConvertToTemplate -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-totemplate"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm.opaque_ref  # now a real (halted) VM
    $ref = $vm.opaque_ref
    Write-Host "is_a_template after provision: $((Get-XenVM -Ref $ref).is_a_template)"

    # Converting a VM to a custom template is a one-way operation.
    $vm | Set-XenVM -IsATemplate $true
    Write-Host "is_a_template after convert:  $((Get-XenVM -Ref $ref).is_a_template)"

    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "OK: convert-to-template"
    $session | Disconnect-XenServer
}
