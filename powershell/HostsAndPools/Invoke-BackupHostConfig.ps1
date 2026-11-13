function Invoke-BackupHostConfig {
    <#
    .SYNOPSIS
        Back up a host's configuration.
    .DESCRIPTION
        Download a host's configuration backup and verify it downloaded; optionally stage it back onto
        that same host's backup partition, ready for a restore done from the installer.
    .EXAMPLE
        Invoke-BackupHostConfig -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [bool]$Restore = $false
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
    $vmHost = Get-XenHost -Ref (Get-XenPool).master
    $hostUrl = Get-HostUrl -Url $Url -Address $vmHost.address
    Write-Host "Backing up $($vmHost.name_label)"

    # Both halves are served only by whichever host physically accepted the HTTP connection - the
    # handler ignores any ref= in the query string entirely, there is no forwarding to another pool
    # member. So backing up/restoring a host means opening the connection to THAT host's own address,
    # not to the pool's (coordinator) URL. ref= is kept in the query string purely for log-readability
    # (a real host ignores it). Still pure PowerShell: Connect-Example has already trusted the server's
    # certificate.
    #
    # -OutFile/-InFile below already stream straight to/from disk rather than buffering the whole file,
    # and there is no idle-connection step to take after the transfer (unlike the Python/Java ports):
    # this module's cmdlets dispatch through the C# binding's Session/JsonRpcClient, whose
    # PerformPostRequest opens a brand-new HttpClient per XenAPI call and disposes it immediately
    # afterwards - there is no kept-alive session connection that a long transfer could leave idle.
    $path = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-host-$([guid]::NewGuid().Guid).backup"
    Invoke-WebRequest -UseBasicParsing -OutFile $path -TimeoutSec 10 `
        -Uri "$hostUrl/host_backup?session_id=$($session.opaque_ref)&ref=$($vmHost.opaque_ref)"
    $size = (Get-Item $path).Length
    if ($size -eq 0) { throw "$path came back empty" }
    Write-Host "  wrote $size bytes to $(Split-Path $path -Leaf)"

    if ($Restore) {
        # host-restore does not restore the host there and then: it only writes the archive over that
        # host's currently inactive backup partition, ready for the next boot. It takes effect only once
        # that host is booted from the installer and Restore is chosen there.
        Restore-ExampleHostConfig -Session $session -HostUrl $hostUrl -VMHost $vmHost -Path $path
        Write-Host ("  staged it on $($vmHost.name_label)'s backup partition - it takes effect only after " +
            "booting that host from the installer and choosing Restore")
    }
    else {
        Write-Host "  not restoring it (pass -Restore `$true to stage it on $($vmHost.name_label)'s backup partition)"
    }

    Remove-Item $path
    Write-Host "OK: backup-host-config"
    $session | Disconnect-XenServer
}

function Get-HostUrl {
    <#
    .SYNOPSIS
        Build the URL for a given host's own address, keeping the scheme and port the caller originally
        connected with (a host's management address carries no port of its own).
    #>
    param([string]$Url, [string]$Address)
    $uri = [System.Uri]$Url
    $port = if ($uri.Port -gt 0) { ":$($uri.Port)" } else { "" }
    return "$($uri.Scheme)://$Address$port"
}

function Restore-ExampleHostConfig {
    <#
    .SYNOPSIS
        Uploads a backup to a host - over a connection opened to THAT host's own address - and raises if
        the task reports it was refused.
    .DESCRIPTION
        An upload answers 200 as soon as it has read the request headers, because the client waits for that
        before it starts sending the file. The outcome therefore cannot be in the status line: it arrives on
        a task you create first, name in the URL, and poll once the upload has finished.
    #>
    param($Session, [string]$HostUrl, $VMHost, [string]$Path)

    $task = New-XenTask -Label 'host_restore' -Description 'restoring a configuration backup' -PassThru
    try {
        # The timeout covers the whole transfer: a backup is hundreds of MB, so allow for a slow network.
        Invoke-WebRequest -UseBasicParsing -Method Put -InFile $Path -TimeoutSec 1800 `
            -Uri ("$HostUrl/host_restore?session_id=$($Session.opaque_ref)" +
                  "&ref=$($VMHost.opaque_ref)&task_id=$($task.opaque_ref)") | Out-Null

        while ((Get-XenTask -Ref $task).status -eq 'pending') { Start-Sleep -Milliseconds 500 }
        $finished = Get-XenTask -Ref $task
        if ($finished.status -ne 'success') {
            throw "refused ($($finished.error_info[-1]))"
        }
    }
    finally {
        Remove-XenTask -Ref $task
    }
}
