function Invoke-VmFromSnapshot {
    <#
    .SYNOPSIS
        Create a VM and a template from a snapshot.
    .DESCRIPTION
        Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.
    .EXAMPLE
        Invoke-VmFromSnapshot -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = 'db-01'
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # A snapshot is a VM record with is_a_snapshot (and is_a_template) set, and cloning it gives a custom
    # template that stands on its own while the snapshot stays put.
    $vm = Get-XenVM -Name $VmName | Select-Object -First 1
    $snapshot = $vm | Invoke-XenVM -XenAction Snapshot -NewName 'sdk-example-source-snapshot' -PassThru
    Write-Host "Snapshot of $VmName taken"

    # A clone of a snapshot is a template, not another snapshot: it stands on its own instead of being
    # filed under the original VM. Provision it to get an ordinary VM you can start.
    $newVm = $snapshot | Invoke-XenVM -XenAction Clone -NewName 'sdk-example-vm-from-snapshot' -PassThru
    Invoke-VmProvision -Ref $newVm
    Write-Host "  new VM:      $($newVm.name_label) (is_a_template=$((Get-XenVM -Ref $newVm).is_a_template))"

    # Another clone, left as the template it already is: a starting point to stamp more VMs from.
    $template = $snapshot | Invoke-XenVM -XenAction Clone -NewName 'sdk-example-template-from-snapshot' -PassThru
    Write-Host "  new template:$($template.name_label) (is_a_template=$((Get-XenVM -Ref $template).is_a_template))"

    # Each clone made its own disks, and the snapshot has its own snapshot disks; destroy them all.
    foreach ($ref in @($newVm, $template, $snapshot)) {
        Remove-VmAndDisks -Ref $ref
    }
    Write-Host "OK: vm-from-snapshot"
    $session | Disconnect-XenServer
}
