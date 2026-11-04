function Invoke-ExportImportVm {
    <#
    .SYNOPSIS
        Export and import a VM.
    .DESCRIPTION
        Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside the
        API rather than API calls, so the session id travels in the query string.
    .EXAMPLE
        Invoke-ExportImportVm -Url https://xenserver -UserName root -Password $password -VmName db-01
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = 'db-01'
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # Name the VM: an export carries every block of its disks, so which VM matters (a large one takes a
    # long time, and fills the disk). Only a halted VM can be exported: its disks must not be changing
    # underneath the copy.
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    if ($vm.power_state -ne 'Halted') { throw "$VmName must be halted to be exported" }
    Write-Host "Exporting $VmName"

    # Export and import are HTTP transfers alongside the API rather than API calls, so the session id
    # travels in the query string. Still pure PowerShell: Connect-Example has already trusted the
    # server's certificate.
    # A unique file, not a fixed name: an export is a real file on disk and two of them running at
    # once would otherwise fight over it.
    $path = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-export-$([guid]::NewGuid().Guid).xva"
    try {
        # Stream both directions: -OutFile/-InFile stream to and from the file rather than buffering the
        # whole transfer in memory, as a real VM's export can be gigabytes.
        Invoke-WebRequest -Uri "$Url/export?session_id=$($session.opaque_ref)&uuid=$($vm.uuid)" `
            -OutFile $path -UseBasicParsing
        Write-Host ("  wrote {0:N1} MiB to {1}" -f ((Get-Item $path).Length / 1MB), (Split-Path $path -Leaf))

        # An XVA is a tar: ova.xml describes the VM, and the disk blocks follow in 1 MiB pieces, each with
        # its own checksum.
        $names = Get-TarEntryName -Path $path
        Write-Host ("  archive holds {0} and {1} disk block(s)" -f
            $names[0], (@($names | Where-Object { -not $_.EndsWith('.checksum') }).Count - 1))

        # The imported VM's ref is NOT in the /import response body on a real host - the only place it
        # appears is the task named in the task_id query parameter, so create one, pass it, and read the
        # task's result once the upload finishes, the same pattern backup-host-config/wait-for-task use.
        $task = New-XenTask -Label 'vm_import' -Description "importing $VmName back" -PassThru
        try {
            Invoke-WebRequest -Uri "$Url/import?session_id=$($session.opaque_ref)&task_id=$($task.opaque_ref)" `
                -Method Put -InFile $path -UseBasicParsing | Out-Null
            while ((Get-XenTask -Ref $task.opaque_ref).status -eq 'pending') { Start-Sleep -Milliseconds 500 }
            $finished = Get-XenTask -Ref $task.opaque_ref
            if ($finished.status -ne 'success') { throw "import failed: $($finished.error_info -join ' ')" }
            # The result lists the imported VMs (<value><array><data>OpaqueRef:...</data></array></value>
            # on a real host), so take the first reference in it.
            $imported = [regex]::Match($finished.result, 'OpaqueRef:[^<]+').Value
        }
        finally {
            Remove-XenTask -Ref $task.opaque_ref
        }
        Write-Host "  imported as $((Get-XenVM -Ref $imported).name_label)"

        # The import brought its own disks along; destroy those too, not just the VM record.
        Remove-VmAndDisks -Ref $imported
        Write-Host "OK: export-import-vm"
    }
    finally {
        # Always clean up the file, on failure too: a real export is gigabytes, not worth leaving behind.
        Remove-Item $path -ErrorAction SilentlyContinue
    }
    $session | Disconnect-XenServer
}

function Get-TarEntryName {
    <#
    .SYNOPSIS
        A tar's entry names, read from the format itself.
    .DESCRIPTION
        The name is the first 100 bytes of each 512-byte header and the size is octal at offset 124, with
        every file padded to the next 512-byte boundary.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $names = @()
        $header = New-Object byte[] 512
        while ($stream.Read($header, 0, 512) -eq 512) {
            $name = ([Text.Encoding]::ASCII.GetString($header, 0, 100) -replace "`0.*$", '').Trim()
            if (-not $name) { break }        # the end-of-archive marker
            $names += $name
            $octal = ([Text.Encoding]::ASCII.GetString($header, 124, 12) -replace "`0.*$", '').Trim()
            $size = if ($octal) { [Convert]::ToInt64($octal, 8) } else { 0 }
            $stream.Seek([math]::Ceiling($size / 512) * 512, [IO.SeekOrigin]::Current) | Out-Null
        }
        return $names
    }
    finally { $stream.Dispose() }
}
