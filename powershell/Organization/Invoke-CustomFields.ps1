function Invoke-CustomFields {
    <#
    .SYNOPSIS
        Custom fields.
    .DESCRIPTION
        Attach and read a custom name/value field on a VM -- arbitrary metadata you define. A management
        client only shows a field once it has been DEFINED for the pool; the value on the object is a
        separate step. This sample does both.
    .EXAMPLE
        Invoke-CustomFields -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $customFieldBaseKey = "XenCenter.CustomFields"
    $fieldName = "Owner"
    $fieldKey = "$customFieldBaseKey.$fieldName"

    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $pool = Get-XenPool | Select-Object -First 1

    # The pool's custom field DEFINITIONS (name and type, String or Date) live in a small XML document in
    # pool.gui_config["XenCenter.CustomFields"] (the key keeps its historical name); a client shows no
    # field without one, no matter what value an object carries under XenCenter.CustomFields.<name>.
    $previousXml = $pool.gui_config[$customFieldBaseKey]
    [xml]$doc = if ($previousXml) { $previousXml } else { "<CustomFieldDefinitions />" }
    $addedDefinition = -not ($doc.CustomFieldDefinitions.CustomFieldDefinition |
        Where-Object { $_.name -eq $fieldName })
    if ($addedDefinition) {
        $definition = $doc.CreateElement("CustomFieldDefinition")
        $definition.SetAttribute("name", $fieldName)
        $definition.SetAttribute("type", "String")
        [void]$doc.DocumentElement.AppendChild($definition)

        $guiConfig = @{}
        foreach ($k in $pool.gui_config.Keys) { $guiConfig[$k] = $pool.gui_config[$k] }
        $guiConfig[$customFieldBaseKey] = $doc.OuterXml
        $pool | Set-XenPool -GuiConfig $guiConfig
    }
    Write-Host "Field defined: $addedDefinition"

    # With the field defined, giving it a value on an object is a plain other_config write.
    # Set-XenVM -OtherConfig replaces the whole map, so merge the field into a copy; Remove-XenVMProperty
    # -OtherConfig then drops it again by key.
    $oc = @{}
    foreach ($k in $vm.other_config.Keys) { $oc[$k] = $vm.other_config[$k] }
    $oc[$fieldKey] = "Platform Team"
    $vm | Set-XenVM -OtherConfig $oc
    Write-Host "Custom field Owner = $((Get-XenVM -Ref $vm).other_config[$fieldKey])"

    $vm | Remove-XenVMProperty -OtherConfig $fieldKey
    if ($addedDefinition) {
        # Only this sample's own definition is ours to remove, and only by putting back the pool's
        # previous gui_config value exactly (there may be other definitions alongside it).
        if ($previousXml) {
            $guiConfig = @{}
            foreach ($k in $pool.gui_config.Keys) { $guiConfig[$k] = $pool.gui_config[$k] }
            $guiConfig[$customFieldBaseKey] = $previousXml
            $pool | Set-XenPool -GuiConfig $guiConfig
        } else {
            $pool | Remove-XenPoolProperty -GuiConfig $customFieldBaseKey
        }
    }
    Write-Host "OK: custom-fields"
    $session | Disconnect-XenServer
}
