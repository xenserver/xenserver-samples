function Invoke-OfflinePoolUpdate {
    <#
    .SYNOPSIS
        Update an air-gapped pool from a bundle.
    .DESCRIPTION
        Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make a
        bundle repository the pool's update repository, upload the bundle, list the updates it offers, then
        apply them host by host - coordinator first, moving each host's VMs to the rest of the pool - so the
        VMs keep running throughout.

        Check first, before changing anything, that the update can go through: HA and Workload Balancing off,
        no host or VM with mandatory guidance still pending from an earlier update, and every host able to
        empty. Then make a repository of the bundle kind the pool's only enabled repository - a pool can have
        only one (introducing a second fails with BUNDLE_REPOSITORY_ALREADY_EXISTS), so use the existing one
        if there is one.

        Send-XenBundle uploads the bundle with a task to report on: the pool unpacks the bundle, checks its
        signature and syncs its updates before the task completes. Receive-XenUpdates then lists what the
        bundle offers and the hash to apply it with, and Update-Hosts applies it to each host in turn as
        Invoke-RollingPoolUpdate does. Finally report the guidance left for VMs, such as restarting one to
        pick the update up - that is the VM owner's call.

        A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts the
        pool's previous repositories back afterwards so that it can run again on a test pool.
    .EXAMPLE
        Invoke-OfflinePoolUpdate -Url https://xenserver -UserName root -Password $password -BundlePath .\XS9-update.xsbundle
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$BundlePath
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1
    $hosts = Get-HostsCoordinatorFirst
    Assert-HaAndWlbOff -Pool $pool
    Assert-NoPendingGuidance
    Assert-HostsCanBeEvacuated -Hosts $hosts

    $previous = @($pool.repositories)
    $existing = Get-XenRepository | Where-Object { $_.origin -eq 'bundle' } | Select-Object -First 1
    $repo = if ($existing) { $existing } else {
        # Repository.introduce_bundle is a static-style create, so pass the NULL ref for the (ignored)
        # instance param.
        Invoke-XenRepository -Ref 'OpaqueRef:NULL' -XenAction IntroduceBundle -NameLabel "sdk-example-offline" `
            -NameDescription "Updates from uploaded bundles" -PassThru
    }
    try {
        $pool | Set-XenPool -Repositories @($repo)
        Write-Host ("Pool repositories: " + ((Get-XenPool -Ref $pool).repositories |
            ForEach-Object { (Get-XenRepository -Ref $_).name_label }) -join ", ")

        $coordinator = Get-XenHost -Ref $pool.master
        # Send-XenBundle/Receive-XenUpdates are HTTP helpers, not XenAPI calls: -TaskRef travels in the
        # request itself, so it needs the opaque ref string, not the task object.
        $task = New-XenTask -Label "sdk-example-bundle-upload" -Description "" -PassThru
        try {
            Send-XenBundle -XenHost $coordinator.address -Path $BundlePath -TaskRef $task.opaque_ref `
                -NoWarnCertificates -NoWarnNewCertificates
            $task | Wait-XenTask -ShowProgress
            $finished = Get-XenTask -Ref $task
            if ($finished.status -ne 'success') { throw "bundle upload failed: $($finished.error_info -join ' ')" }
        }
        finally {
            Remove-XenTask -Ref $task
        }
        Write-Host "Uploaded $(Split-Path $BundlePath -Leaf)"

        $json = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-updates-$([guid]::NewGuid().Guid).json"
        $task = New-XenTask -Label "sdk-example-updates" -Description "" -PassThru
        try {
            Receive-XenUpdates -XenHost $coordinator.address -Path $json -TaskRef $task.opaque_ref `
                -NoWarnCertificates -NoWarnNewCertificates
            $task | Wait-XenTask
        }
        finally {
            Remove-XenTask -Ref $task
        }
        $available = Get-Content -Raw -Path $json | ConvertFrom-Json
        Remove-Item $json
        $updates = @($available.updates)
        Write-Host "Updates in the bundle: $($updates.Count)"
        foreach ($update in $updates) { Write-Host "  $($update.id): $($update.summary)" }
        if ($updates.Count -gt 0) {
            $session = Update-Hosts -Session $session -Url $Url -UserName $UserName -Password $Password `
                -Hosts $hosts -Hash $available.hash
        }
    }
    finally {
        # Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
        $pool | Set-XenPool -Repositories $previous
        if (-not $existing) { $repo | Invoke-XenRepository -XenAction Forget }
    }
    Write-VmGuidance
    Write-Host "OK: offline-pool-update"
    $session | Disconnect-XenServer
}
