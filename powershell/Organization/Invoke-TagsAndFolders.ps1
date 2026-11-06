function Invoke-TagsAndFolders {
    <#
    .SYNOPSIS
        Tag and organize objects.
    .DESCRIPTION
        Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type),
        place the VM in a folder, read it all back, then tidy up.
    .EXAMPLE
        Invoke-TagsAndFolders -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $vmHost = Get-XenHost | Select-Object -First 1

    # Tags work on any object type (VM, host, SR, network, …): Add-Xen* appends a tag, the matching
    # Remove-Xen*Property drops it.
    $vm | Add-XenVM -Tags "web"
    $vmHost | Add-XenHost -Tags "gold"
    Write-Host "VM tags:   $((Get-XenVM -Ref $vm).tags -join ', ')"
    Write-Host "Host tags: $((Get-XenHost -Ref $vmHost).tags -join ', ')"

    # Folder placement lives in other_config["folder"] as a leading-slash path; merge it into the map.
    $current = $vm.other_config
    $oc = @{}
    foreach ($k in $current.Keys) { $oc[$k] = $current[$k] }
    $oc["folder"] = "/Production/Web"
    $vm | Set-XenVM -OtherConfig $oc
    Write-Host "VM folder: $((Get-XenVM -Ref $vm).other_config['folder'])"

    # Tidy up.
    $vm | Remove-XenVMProperty -Tags "web"
    $vmHost | Remove-XenHostProperty -Tags "gold"
    $vm | Remove-XenVMProperty -OtherConfig "folder"
    Write-Host "OK: tags-and-folders"
    $session | Disconnect-XenServer
}
