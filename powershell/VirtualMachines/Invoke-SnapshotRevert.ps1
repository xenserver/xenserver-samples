function Invoke-SnapshotRevert {
    <#
    .SYNOPSIS
        Snapshot & revert.
    .DESCRIPTION
        Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a
        risky change.
    .EXAMPLE
        Invoke-SnapshotRevert -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName,
        [string]$SnapshotName = "sdk-example-snapshot"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    Write-Host "Snapshotting VM: $($vm.name_label)"
    $wasRunning = (Get-XenVM -Ref $vm).power_state -eq 'Running'

    $snap = $vm | Invoke-XenVM -XenAction Snapshot -NewName $SnapshotName -PassThru
    Write-Host "Created snapshot: $($snap.uuid)"

    # A client shows a thumbnail of what was on screen when the snapshot was taken, captured from the
    # VM's console at that moment. It is an HTTP transfer alongside the API, not an API call, so the
    # session id travels in the query string. ref names the VM's VNC (rfb) console (the VM itself
    # works too). Only a running VM has a console to capture, and a host that can't reach it answers
    # 404 or 500 instead of an image: the picture is incidental, so carry on. Still pure PowerShell:
    # Connect-Example has already trusted the server's certificate.
    if ((Get-XenVM -Ref $vm).power_state -eq 'Running') {
        $console = (Get-XenVM -Ref $vm).consoles |
            ForEach-Object { Get-XenConsole -Ref $_ } | Where-Object { $_.protocol -eq 'rfb' } |
            Select-Object -First 1
        # An HTTP error status throws in both Windows PowerShell 5.1 and PowerShell 7, with the response
        # (and its status code) on the exception. Bound the whole request: a host's 404 here can leave
        # the connection open, and PowerShell 7 then waits for the end of the error body indefinitely -
        # its -TimeoutSec bounds only connecting, -OperationTimeoutSeconds the rest; 5.1's -TimeoutSec
        # covers both. A picture isn't worth stalling the workflow for.
        $wait = if ($PSVersionTable.PSEdition -eq 'Core') { @{ OperationTimeoutSeconds = 30 } } else { @{ TimeoutSec = 30 } }
        try {
            $thumb = Invoke-WebRequest -UseBasicParsing @wait `
                -Uri "$Url/vncsnapshot?session_id=$($session.opaque_ref)&ref=$($console.opaque_ref)"
            Write-Host "Thumbnail:      $($thumb.RawContentLength) bytes of PNG"
        }
        catch {
            $reason = if ($_.Exception.Response) { "the host answered HTTP $([int]$_.Exception.Response.StatusCode)" }
                      else { "no answer: $($_.Exception.Message)" }
            Write-Host "Thumbnail:      none ($reason)"
        }
    }
    else {
        Write-Host "Thumbnail:      none (the VM is not running, so it has no console)"
    }

    # Revert the VM to the snapshot. The native cmdlet takes the VM (piped in) and the snapshot to
    # restore via -Snapshot. Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-
    # down a running VM before reverting it), even if it was Running a moment ago - restart it
    # afterwards if that's how we found it, so the workflow actually restores what it changed.
    $vm | Invoke-XenVM -XenAction Revert -Snapshot $snap
    Write-Host "Reverted VM to the snapshot."

    if ($wasRunning) {
        $vm | Invoke-XenVM -XenAction Start
        Write-Host "Restarted the VM (it was running before the revert)."
    }

    # A snapshot is itself a (special) VM record, with its own snapshot disks; destroy both to clean up
    # (the source VM's disks are untouched - they are not the snapshot's).
    Remove-VmAndDisks -Ref $snap
    Write-Host "OK: snapshot-revert"
    $session | Disconnect-XenServer
}
