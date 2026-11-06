function Invoke-ConfigureOfflineUpdates {
    <#
    .SYNOPSIS
        Configure updates for an air-gapped pool.
    .DESCRIPTION
        Switch a pool with no internet access to offline updates: make an update bundle repository the pool's
        only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it makes
        available, then tidy up.

        A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool
        needs a repository of the bundle kind (it can have only one: introducing a second fails with
        BUNDLE_REPOSITORY_ALREADY_EXISTS, so use the existing one), and it must be the pool's only enabled
        repository. Send-XenBundle uploads the bundle with a task to report on: the pool unpacks and checks
        it, and the task says how that went. Receive-XenUpdates then lists what the bundle offers each host,
        and Invoke-XenHost -XenAction ApplyUpdates applies it with the hash in that list (see
        Invoke-ApplyUpdate). Without BundlePath this only switches the channel and back.
    .EXAMPLE
        Invoke-ConfigureOfflineUpdates -Url https://xenserver -UserName root -Password $password -BundlePath .\XS9-update.xsbundle
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$BundlePath
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    # Remember the pool's own repositories, to put them back afterwards.
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

        if ($BundlePath) {
            $coordinator = Get-XenHost -Ref $pool.master
            $task = New-XenTask -Label "sdk-example-bundle-upload" -Description "" -PassThru
            # Send-XenBundle/Receive-XenUpdates are HTTP helpers, not XenAPI calls: -TaskRef travels in the
            # request itself, so it needs the opaque ref string, not the task object.
            Send-XenBundle -XenHost $coordinator.address -Path $BundlePath -TaskRef $task.opaque_ref `
                -NoWarnCertificates -NoWarnNewCertificates
            $task | Wait-XenTask -ShowProgress
            $finished = Get-XenTask -Ref $task
            Remove-XenTask -Ref $task
            if ($finished.status -ne 'success') { throw "bundle upload failed: $($finished.error_info -join ' ')" }
            Write-Host "Uploaded $(Split-Path $BundlePath -Leaf)"

            $json = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-updates-$([guid]::NewGuid().Guid).json"
            $task = New-XenTask -Label "sdk-example-updates" -Description "" -PassThru
            Receive-XenUpdates -XenHost $coordinator.address -Path $json -TaskRef $task.opaque_ref `
                -NoWarnCertificates -NoWarnNewCertificates
            $task | Wait-XenTask
            Remove-XenTask -Ref $task
            $available = Get-Content -Raw -Path $json | ConvertFrom-Json
            Remove-Item $json
            Write-Host "Updates in the bundle: $(@($available.updates).Count) (apply them with hash $($available.hash))"
        }
        else {
            Write-Host "No bundle given: pass bundle_path to upload one"
        }
    }
    finally {
        # Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
        $pool | Set-XenPool -Repositories $previous
        if (-not $existing) { $repo | Invoke-XenRepository -XenAction Forget }
    }
    Write-Host "OK: configure-offline-updates"
    $session | Disconnect-XenServer
}
