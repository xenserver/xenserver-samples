function Invoke-BackupHostConfig {
    <#
    .SYNOPSIS
        Back up a host's configuration.
    .DESCRIPTION
        Download a host's configuration backup and hand it back as a restore would — and watch another
        host's backup be refused.
    .EXAMPLE
        Invoke-BackupHostConfig -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $hosts = @(Get-XenHost)
    $vmHost = $hosts[0]
    $hostUrl = Get-HostUrl -Url $Url -Address $vmHost.address
    Write-Host "Backing up $($vmHost.name_label)"

    # Both halves are served only by whichever host physically accepted the HTTP connection - the
    # handler ignores any ref= in the query string entirely, there is no forwarding to another pool
    # member. So backing up/restoring a host means opening the connection to THAT host's own address,
    # not to the pool's (coordinator) URL - a restore sent to the wrong host's connection silently
    # restores the WRONG host, not the one named by ref=. ref= is kept in the query string purely for
    # log-readability (a real host ignores it; it is not what makes this correct). Still pure
    # PowerShell: Connect-Example has already trusted the server's certificate.
    #
    # -OutFile/-InFile below already stream straight to/from disk rather than buffering the whole file,
    # and there is no idle-connection step to take after the transfer (unlike the Python/Java ports):
    # this module's cmdlets dispatch through the C# binding's Session/JsonRpcClient, whose
    # PerformPostRequest opens a brand-new HttpClient per XenAPI call and disposes it immediately
    # afterwards - there is no kept-alive session connection that a long transfer could leave idle.
    $path = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-host-$([guid]::NewGuid().Guid).backup"
    Invoke-WebRequest -UseBasicParsing -OutFile $path -TimeoutSec 10 `
        -Uri "$hostUrl/host_backup?session_id=$($session.opaque_ref)&ref=$($vmHost.opaque_ref)"
    Write-Host "  wrote $((Get-Item $path).Length) bytes to $(Split-Path $path -Leaf)"

    Write-Host ("  restoring it to {0}: {1}" -f $vmHost.name_label,
        (Restore-ExampleHostConfig -Session $session -HostUrl $hostUrl -VMHost $vmHost -Path $path))
    if ($hosts.Count -gt 1) {
        # A real pool's hosts are all reachable from a management client; guard against a topology
        # where a second host's address isn't actually routable from the caller, and turn that into an
        # informative message instead of a crash.
        $other = $hosts[1]
        $otherUrl = Get-HostUrl -Url $Url -Address $other.address
        try {
            $result = Restore-ExampleHostConfig -Session $session -HostUrl $otherUrl -VMHost $other -Path $path
        }
        catch {
            $result = "could not connect to $otherUrl directly ($($_.Exception.Message))"
        }
        Write-Host ("  restoring it to {0}: {1}" -f $other.name_label, $result)
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
        Uploads a backup to a host - over a connection opened to THAT host's own address - and reports what
        the task says about it.
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

        while ((Get-XenTask -Ref $task.opaque_ref).status -eq 'pending') { Start-Sleep -Milliseconds 500 }
        $finished = Get-XenTask -Ref $task.opaque_ref
        if ($finished.status -eq 'success') { return 'accepted' }
        return "refused ($($finished.error_info[-1]))"
    }
    finally {
        Remove-XenTask -Ref $task.opaque_ref
    }
}
