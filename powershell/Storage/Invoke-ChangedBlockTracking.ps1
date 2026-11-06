function Invoke-ChangedBlockTracking {
    <#
    .SYNOPSIS
        Back up with changed block tracking.
    .DESCRIPTION
        Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which
        blocks differ, then release the older snapshot's data while keeping the change metadata the next
        incremental needs.
    .EXAMPLE
        Invoke-ChangedBlockTracking -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.VBDs.Count -gt 0
    } | Select-Object -First 1
    Write-Host "Backing up $($vm.name_label)"

    # CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it. It
    # can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
    $live = Get-FirstDisk -Snapshot $vm
    $wasEnabled = (Get-XenVDI -Ref $live).cbt_enabled
    if (-not $wasEnabled) { Invoke-XenVDI -Ref $live -XenAction EnableCbt }

    $first = Invoke-XenVM -VM $vm -XenAction Snapshot -NewName 'cbt-backup-1' -PassThru
    $second = Invoke-XenVM -VM $vm -XenAction Snapshot -NewName 'cbt-backup-2' -PassThru
    # Re-fetch the snapshots: the object -PassThru hands back is the VM as it was when created, and its
    # disks are attached a moment later, so its VBDs list is empty.
    $vdiFrom = Get-FirstDisk -Snapshot (Get-XenVM -Ref $first)
    $vdiTo = Get-FirstDisk -Snapshot (Get-XenVM -Ref $second)

    # One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup reads
    # only those blocks, over NBD.
    # BOTH disks go in the dynamic parameters. -Ref only names the object the confirmation prompt talks
    # about; the call itself is made from -VdiFrom and -VdiTo, so passing only one sends a null for the
    # other and the server answers HANDLE_INVALID with an empty reference. (Dynamic parameters are keyed
    # on -XenAction, which is why they never show in (Get-Command).Parameters.)
    $encoded = Invoke-XenVDI -Ref $vdiFrom -XenAction ListChangedBlocks `
        -VdiFrom (Get-XenVDI -Ref $vdiFrom | ConvertTo-XenRef) `
        -VdiTo (Get-XenVDI -Ref $vdiTo | ConvertTo-XenRef) -PassThru
    $bitmap = [Convert]::FromBase64String($encoded)
    $changed = 0
    foreach ($byte in $bitmap) {
        $b = $byte
        while ($b) { $changed += $b -band 1; $b = $b -shr 1 }
    }
    $size = (Get-XenVDI -Ref $vdiTo).virtual_size
    Write-Host ("  {0} blocks of {1} changed ({2:N1} MiB to copy, not {3:N1} MiB)" -f
        $changed, ($bitmap.Length * 8), ($changed * 64 / 1024), ($size / 1MB))

    # Release the older snapshot's blocks but keep its change metadata, so the next incremental can
    # still diff against it. DataDestroy refuses a disk that a VM still uses (VDI_IN_USE), so remove the
    # older snapshot's VM record first, as a backup tool does. The VDI record stays; its type changes.
    Remove-XenVM -Ref $first
    Invoke-XenVDI -Ref $vdiFrom -XenAction DataDestroy
    $after = Get-XenVDI -Ref $vdiFrom
    Write-Host "  older snapshot is now type=$($after.type), still cbt_enabled=$($after.cbt_enabled)"

    # Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own disk if
    # this example switched it on.
    Remove-VmAndDisks -Ref $second
    Remove-XenVDI -Ref $vdiFrom
    if (-not $wasEnabled) { Invoke-XenVDI -Ref $live -XenAction DisableCbt }
    Write-Host "OK: changed-block-tracking"
    $session | Disconnect-XenServer
}

function Get-FirstDisk {
    <#
    .SYNOPSIS
        The VDI behind a snapshot's first real disk (a CD drive is a VBD too).
    #>
    param([Parameter(Mandatory = $true)]$Snapshot)
    foreach ($vbdRef in $Snapshot.VBDs) {
        $vbd = Get-XenVBD -Ref $vbdRef
        if ($vbd.type -eq 'Disk') { return $vbd.VDI }
    }
    throw "no disk found"
}
