function Invoke-ExportImportVdi {
    <#
    .SYNOPSIS
        Copy a disk's contents.
    .DESCRIPTION
        Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk,
        then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.

        A disk's contents are not XenAPI calls: GET /export_raw_vdi reads them and PUT /import_raw_vdi
        writes them, both alongside the API with the session id in the query string. format=raw is every
        byte of the disk, so a raw export is as large as the disk's virtual size (format=vhd sends only the
        allocated blocks). Name a task in task_id to learn how the transfer ended: an HTTP 200 only means
        the server accepted the request.
    .EXAMPLE
        Invoke-ExportImportVdi -Url https://xenserver -UserName root -Password $password -SrName 'Shared NFS'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$SrName = 'Shared NFS'
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $sr = Get-XenSR -Name $SrName | Select-Object -First 1
    if (-not $sr) { throw "No SR named '$SrName' was found." }
    $size = 8MB

    $original = New-XenVDI -NameLabel "sdk-example-raw-source" -SR $sr -VirtualSize $size `
        -Type user -Sharable $false -ReadOnly $false -PassThru
    $copy = New-XenVDI -NameLabel "sdk-example-raw-copy" -SR $sr -VirtualSize $size `
        -Type user -Sharable $false -ReadOnly $false -PassThru
    # Files, not byte arrays, for the transfers: -InFile and -OutFile stream them.
    $source = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-raw-$([guid]::NewGuid().Guid)"
    $exported = "$source.exported"
    try {
        $data = [byte[]]::new($size)
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($data)
        [IO.File]::WriteAllBytes($source, $data)

        Send-RawVdi -Session $session -Url $Url -Vdi $original -Path $source
        Write-Host "Uploaded $($size / 1MB) MiB into $($original.name_label)"

        Receive-RawVdi -Session $session -Url $Url -Vdi $original -Path $exported
        Write-Host "Downloaded $((Get-Item $exported).Length / 1MB) MiB of raw contents"

        Send-RawVdi -Session $session -Url $Url -Vdi $copy -Path $exported
        Write-Host "Copied them into $($copy.name_label)"

        Receive-RawVdi -Session $session -Url $Url -Vdi $copy -Path $exported
        $same = (Get-FileHash $exported -Algorithm SHA256).Hash -eq (Get-FileHash $source -Algorithm SHA256).Hash
        Write-Host "The copy $(if ($same) { 'matches' } else { 'DIFFERS FROM' }) the original"
        if (-not $same) { throw "the copied disk does not match the data uploaded" }
    }
    finally {
        Remove-Item $source, $exported -ErrorAction SilentlyContinue
        $original, $copy | ForEach-Object { Remove-XenVDI -Ref $_ }
    }
    Write-Host "OK: export-import-vdi"
    $session | Disconnect-XenServer
}

function Send-RawVdi {
    <#
    .SYNOPSIS
        PUT /import_raw_vdi: write a file's bytes into a disk, waiting for the transfer's task.
    #>
    param($Session, [string]$Url, $Vdi, [string]$Path)
    Invoke-RawVdiTransfer -Session $Session -Url $Url -Vdi $Vdi -Path $Path -Method Put -Endpoint import_raw_vdi
}

function Receive-RawVdi {
    <#
    .SYNOPSIS
        GET /export_raw_vdi: read a disk's raw contents into a file, waiting for the transfer's task.
    #>
    param($Session, [string]$Url, $Vdi, [string]$Path)
    Invoke-RawVdiTransfer -Session $Session -Url $Url -Vdi $Vdi -Path $Path -Method Get -Endpoint export_raw_vdi
}

function Invoke-RawVdiTransfer {
    <#
    .SYNOPSIS
        One raw transfer of a disk's contents, waiting for its task to finish.
    #>
    param($Session, [string]$Url, $Vdi, [string]$Path, [string]$Method, [string]$Endpoint)
    $task = New-XenTask -Label "sdk-example-$Endpoint" -Description "" -PassThru
    try {
        $uri = "$Url/$Endpoint" + "?session_id=$($Session.opaque_ref)&task_id=$($task.opaque_ref)" +
            "&vdi=$($Vdi.opaque_ref)&format=raw"
        if ($Method -eq 'Put') { Invoke-WebRequest -Uri $uri -Method Put -InFile $Path -UseBasicParsing | Out-Null }
        else { Invoke-WebRequest -Uri $uri -OutFile $Path -UseBasicParsing }
        while ((Get-XenTask -Ref $task).status -eq 'pending') { Start-Sleep -Milliseconds 500 }
        $finished = Get-XenTask -Ref $task
        if ($finished.status -ne 'success') { throw "$Endpoint failed: $($finished.error_info -join ' ')" }
    }
    finally {
        Remove-XenTask -Ref $task
    }
}
