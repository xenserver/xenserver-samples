function Invoke-SnapshotSchedule {
    <#
    .SYNOPSIS
        Snapshot schedule.
    .DESCRIPTION
        Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention
        limit prune the oldest snapshot away.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName,
        [string]$ScheduleName = "sdk-example-schedule"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }

    $runs = 3
    $retention = 2

    # RetainedSnapshots is the interesting field: the schedule prunes to it every time it runs.
    $vmss = New-XenVMSS -NameLabel $ScheduleName `
        -NameDescription 'Scheduled snapshots created by the SDK example' `
        -Enabled $true -Type snapshot -Frequency daily -RetainedSnapshots $retention `
        -Schedule @{ hour = '2'; min = '0' } -PassThru
    Write-Host "Created schedule: $($vmss.uuid)"

    Set-XenVM -VM $vm -SnapshotSchedule $vmss
    Write-Host "Members:          $((Get-XenVMSS -Ref $vmss).VMs.Count)"

    # Run it three times against a retention of two: the oldest is pruned away each time it runs over the
    # limit. Compare against the snapshots the VM already had, so only the schedule's own are counted
    # (and tidied up below).
    $before = @((Get-XenVM -Ref $vm).snapshots)
    1..$runs | ForEach-Object { Invoke-XenVMSS -Ref $vmss -XenAction SnapshotNow | Out-Null }
    $kept = @((Get-XenVM -Ref $vm).snapshots | Where-Object { $before -notcontains $_ })
    $pruned = if ($runs -gt $kept.Count) { 'the oldest was pruned' } else { 'nothing needed pruning yet' }
    Write-Host "Ran the schedule $runs times; kept $($kept.Count) (retention $retention): $pruned"

    # Tidy up: a schedule with VMs still on it cannot be destroyed (VMSS_HAS_VM), so take the VM off it
    # first. Destroying the schedule leaves the snapshots it took, so destroy those too, with their disks.
    Set-XenVM -VM $vm -SnapshotSchedule 'OpaqueRef:NULL'
    Remove-XenVMSS -Ref $vmss
    $kept | ForEach-Object { Remove-VmAndDisks -Ref $_ }
    Write-Host "OK: snapshot-schedule"
    Disconnect-XenServer -Session $session
}
