function Invoke-DisasterRecovery {
    <#
    .SYNOPSIS
        Recover VMs after a disaster.
    .DESCRIPTION
        Replicate the pool's database to shared storage, read it back as a separate database to see what it
        describes, and recover a VM out of it into a second, standby pool (dr_url).
    .EXAMPLE
        Invoke-DisasterRecovery -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$DrUrl
    )
    # Disaster recovery works by writing the pool's own database out to a storage repository as a disk of
    # type "metadata". That disk can be read back as a SEPARATE database - VDI.open_database hands you a
    # session scoped to it - so the ordinary calls describe the pool as it was replicated rather than the
    # pool you are connected to. Recovering reads from that database and writes into a live pool, which
    # is why the recover call is made on the metadata session and takes a live session as its
    # destination.
    #
    # That destination has to be a DIFFERENT, standby pool: recovering a VM back into the exact pool it
    # was replicated from can't actually succeed with force=false. The VM's uuid already exists there, so
    # VM.recover always takes the replace-or-fail path, and nothing replicated a moment ago from a live
    # database can ever be "newer" than the live object it came from - it fails with
    # VM_TO_IMPORT_IS_NOT_NEWER_VERSION. The one-line "fix" of passing force=true instead would make it
    # succeed by REPLACING (destroying and recreating) the live original - exactly the opposite of what a
    # DR demo should show. A second pool is the only way force=false succeeds (a brand-new VM object, not
    # a replace), and it's what every real DR workflow actually does.
    if (-not $DrUrl) {
        throw "disaster-recovery needs a second pool to recover into: pass dr_url=<url of a standby pool>"
    }
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $drSession = Connect-Example -Url $DrUrl -UserName $UserName -Password $Password

    # Replication needs shared storage the standby pool can attach too, and only block storage (iSCSI,
    # HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. The server checks rather than taking
    # your word for it, so ask each candidate, as XenCenter's DR wizard does.
    $sr = Get-XenSR -SessionOpaqueRef $session.opaque_ref | Where-Object {
        $_.shared -and $_.content_type -ne 'iso'
    } | Where-Object {
        try {
            $_ | Invoke-XenSR -SessionOpaqueRef $session.opaque_ref -XenAction AssertSupportsDatabaseReplication
            $true
        }
        catch { $false }
    } | Select-Object -First 1
    if (-not $sr) { throw "no shared SR here supports database replication (it needs iSCSI or HBA storage)" }
    Write-Host "Replicating pool metadata to $($sr.name_label)"
    $sr | Invoke-XenSR -SessionOpaqueRef $session.opaque_ref -XenAction EnableDatabaseReplication

    # Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from the pool
    # you fail over to: it has the same SR attached, rescans it to see the metadata disk just written,
    # opens the database there, and recovers into itself - VM.recover's session_to has to be a session of
    # the server running the call (HANDLE_INVALID otherwise).
    $drSr = Get-XenSR -SessionOpaqueRef $drSession.opaque_ref | Where-Object { $_.uuid -eq $sr.uuid }
    if (-not $drSr) { throw "the standby pool has not attached $($sr.name_label): attach the same storage there first" }
    $drSr | Invoke-XenSR -SessionOpaqueRef $drSession.opaque_ref -XenAction Scan
    $vdi = Get-XenVDI -SessionOpaqueRef $drSession.opaque_ref |
        Where-Object { $_.type -eq 'metadata' -and $_.SR.opaque_ref -eq $drSr.opaque_ref } | Select-Object -First 1
    Write-Host "  metadata disk: $($vdi.uuid)"

    # Two module limits meet here, so the metadata database is driven over JSON-RPC: Invoke-XenVDI
    # -XenAction OpenDatabase does not hand back the session it opens (even with -PassThru), and
    # -SessionOpaqueRef only accepts sessions the module created itself. Same escape hatch the event API
    # needs, and still pure PowerShell.
    $metadataRef = Invoke-XenMethod -Session $drSession -Method 'VDI.open_database' -Params @($vdi.opaque_ref)
    $metadata = [pscustomobject]@{ opaque_ref = $metadataRef; Url = $drSession.Url }

    # Only real guest VMs are recoverable - exclude templates, control domains and snapshots.
    $allRecords = Invoke-XenMethod -Session $metadata -Method 'VM.get_all_records' -Params @()
    $recoverable = @($allRecords.PSObject.Properties | Where-Object {
            -not $_.Value.is_a_template -and -not $_.Value.is_control_domain -and -not $_.Value.is_a_snapshot
        } | Sort-Object { $_.Value.name_label })
    Write-Host "  the replicated database describes $($recoverable.Count) recoverable VM(s)"

    # Only a VM whose disks are all on storage the standby pool can see can be recovered there - the check
    # runs on the METADATA session, and session_to says where the VM should land: the STANDBY pool's
    # session, not this one. Take the first (by name) that passes, as the DR wizard lists them.
    $target = $recoverable | Where-Object {
        try {
            Invoke-XenMethod -Session $metadata -Method 'VM.assert_can_be_recovered' `
                -Params @($_.Name, $drSession.opaque_ref) | Out-Null
            $true
        }
        catch { $false }
    } | Select-Object -First 1
    if (-not $target) { throw "no VM in the replicated database has all its disks on storage the standby pool can see" }
    $targetUuid = $target.Value.uuid
    $name = $target.Value.name_label
    Write-Host "  recovering $name"

    # force stays false - never true (see above: that's the one-line "fix" that would actually destroy a
    # live VM if ever pointed at the source pool).
    Invoke-XenMethod -Session $metadata -Method 'VM.recover' `
        -Params @($target.Name, $drSession.opaque_ref, $false) | Out-Null

    # It is a real VM on the standby pool now, not merely a call that returned - look it up by the uuid
    # full_restore preserved, not by name, on the DESTINATION session. NO fallback to the source pool: a
    # second pool is the only correct target (see above), so this always looks up and tidies up on the
    # destination only.
    $recovered = Get-XenVM -SessionOpaqueRef $drSession.opaque_ref -Uuid $targetUuid
    Write-Host "  $name is $($recovered.power_state) on the standby pool"

    # Tidy up on the standby pool only, by uuid - never guess by name, and never touch the source pool.
    # Destroy the VM record but NOT its disks: they are the protected pool's own disks on the shared SR,
    # not copies.
    Remove-XenVM -SessionOpaqueRef $drSession.opaque_ref -Ref $recovered.opaque_ref

    $sr | Invoke-XenSR -SessionOpaqueRef $session.opaque_ref -XenAction DisableDatabaseReplication
    Write-Host "OK: disaster-recovery"
    $session | Disconnect-XenServer
    $drSession | Disconnect-XenServer
}
