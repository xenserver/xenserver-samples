function Invoke-ManageCrashDumps {
    <#
    .SYNOPSIS
        Clear a host's crash dumps.
    .DESCRIPTION
        Find the crash dumps a host kept after a failure, report how big and how old they are, then delete
        them to free the space.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # When a host crashes it writes a dump to its local disk and keeps it. They are large, nothing cleans
    # them up, and a host that has crashed more than once accumulates them - so clearing them once support
    # has what it needs is ordinary housekeeping. They belong to the host that wrote them, so clear them a
    # host at a time.
    $xenHost = Get-XenHost | Where-Object { $_.crashdumps.Count -gt 0 } | Select-Object -First 1
    if (-not $xenHost) {
        Write-Host "No crash dumps in this pool - nothing to clear."
        Write-Host "OK: manage-crash-dumps"
        $session | Disconnect-XenServer
        return
    }

    $dumps = @($xenHost.crashdumps | ForEach-Object { Get-XenHostCrashdump -Ref $_.opaque_ref })
    Write-Host "$($xenHost.name_label) has $($dumps.Count) crash dump(s)"
    $total = 0
    foreach ($dump in $dumps) {
        $total += $dump.size
        Write-Host ("  {0:yyyyMMdd'T'HH:mm:ss'Z'}  {1}" -f $dump.timestamp, (Format-Mib $dump.size))
    }
    Write-Host "  $(Format-Mib $total) in total"

    # Deleting a dump frees the space on the host; the host itself is untouched.
    $dumps | Remove-XenHostCrashdump
    Write-Host "  cleared:  $($xenHost.name_label) now has $((Get-XenHost -Ref $xenHost.opaque_ref).crashdumps.Count)"

    Write-Host "OK: manage-crash-dumps"
    $session | Disconnect-XenServer
}

function Format-Mib {
    param([long]$Size)
    "{0} MiB" -f [math]::Floor($Size / 1MB)
}
