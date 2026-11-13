function Invoke-CopyVm {
    <#
    .SYNOPSIS
        Copy a VM.
    .DESCRIPTION
        Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks) —
        distinct from a fast, copy-on-write clone.
    .EXAMPLE
        Invoke-CopyVm -Url https://xenserver -UserName root -Password $password -VmName 'db-01' -SrName 'Shared NFS'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName,
        [Parameter(Mandatory = $true)][string]$SrName,
        [string]$CopyName = "sdk-example-copy"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # A full copy needs a halted source; copy places an independent set of disks on the chosen SR.
    $source = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1
    if (-not $source) { throw "No VM named '$VmName' was found." }
    $sr = Get-XenSR -Name $SrName | Select-Object -First 1
    if (-not $sr) { throw "No SR named '$SrName' was found." }
    Write-Host "Copying '$($source.name_label)' to SR: $($sr.name_label)"

    # VM.copy (like VM.clone) only works on a Halted VM - a running source fails with
    # VM_BAD_POWER_STATE - so shut it down first if it's running, and start it back up again after the
    # copy, rather than assuming the VM is already halted.
    $wasRunning = (Get-XenVM -Ref $source).power_state -eq 'Running'
    if ($wasRunning) { $source | Invoke-XenVM -XenAction CleanShutdown }

    $copy = $source | Invoke-XenVM -XenAction Copy -NewName $CopyName -SR $sr -PassThru
    Write-Host "Copied VM:     $($copy.uuid)"
    Write-Host "Copy has $(@($copy.VBDs).Count) VBD(s), is_a_template = $($copy.is_a_template)"

    if ($wasRunning) { $source | Invoke-XenVM -XenAction Start }

    # Tidy up: destroy the copy and its disks, leaving the source VM intact.
    Remove-VmAndDisks -Ref $copy
    Write-Host "Cleaned up the copied VM (left the source intact)."
    Write-Host "OK: copy-vm"
    $session | Disconnect-XenServer
}
