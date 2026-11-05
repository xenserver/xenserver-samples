function Invoke-CloneVm {
    <#
    .SYNOPSIS
        Clone a VM.
    .DESCRIPTION
        Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy —
        the quick way to stamp out new VMs from a halted "golden" image.
    .EXAMPLE
        Invoke-CloneVm -Url https://xenserver -UserName root -Password $password -VmName 'db-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName,
        [string]$CloneName = "sdk-example-clone"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Unlike Copy (a full, independent copy onto a chosen SR), Clone is a fast copy-on-write
    # duplicate on the same SR - ideal for a halted "golden" VM.
    $source = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $source) { throw "No VM named '$VmName' was found." }

    # VM.clone (like VM.copy) only works on a Halted VM - a running source fails with
    # VM_BAD_POWER_STATE - so shut it down first if it's running, and start it back up again after the
    # clone, rather than assuming the VM is already halted.
    $wasRunning = (Get-XenVM -Ref $source.opaque_ref).power_state -eq 'Running'
    if ($wasRunning) { $source | Invoke-XenVM -XenAction CleanShutdown }

    $clone = $source | Invoke-XenVM -XenAction Clone -NewName $CloneName -PassThru
    Write-Host "Cloned '$($source.name_label)' -> $($clone.name_label)"
    Write-Host "Clone has $(@($clone.VBDs).Count) VBD(s)"

    if ($wasRunning) { $source | Invoke-XenVM -XenAction Start }

    # Tidy up: destroy the clone and its (owned) disks.
    Remove-VmAndDisks -Ref $clone.opaque_ref
    Write-Host "OK: clone-vm"
    $session | Disconnect-XenServer
}
