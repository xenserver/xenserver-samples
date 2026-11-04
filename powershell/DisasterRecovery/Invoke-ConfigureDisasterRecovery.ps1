function Invoke-ConfigureDisasterRecovery {
    <#
    .SYNOPSIS
        Configure disaster recovery.
    .DESCRIPTION
        Turn on pool metadata replication: the pool writes its database - the configuration of its VMs and
        vApps - to a disk on an iSCSI or Fibre Channel SR, as XenCenter's Configure DR dialog does. Have your
        storage array replicate that SR, and the VMs' SRs, to the disaster recovery site; a pool there can
        then recover the VMs from the replica (see Invoke-DisasterRecoveryFailover).
    .EXAMPLE
        Invoke-ConfigureDisasterRecovery -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$SrName
    )
    # Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every host
    # must have the SR attached. The server says which qualify: SR.assert_supports_database_replication
    # fails for any that can't (an NFS SR fails SR_OPERATION_NOT_SUPPORTED), so ask each one rather than
    # guessing from its type, as the Configure DR dialog does. A pool can replicate to up to 8 SRs.
    #
    # Replication is only useful while it is on. So that the example leaves the pool as it found it, it
    # turns replication off again if it was off to start with; in practice, leave it on.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $candidates = @(Get-XenSR | Where-Object { $_.shared -and $_.content_type -ne 'iso' } | Where-Object {
            try {
                $_ | Invoke-XenSR -XenAction AssertSupportsDatabaseReplication
                $true
            }
            catch { $false }
        })
    $names = ($candidates | ForEach-Object { $_.name_label }) -join ', '
    Write-Host "SRs that can hold the pool metadata: $(if ($names) { $names } else { 'none' })"
    if ($SrName) { $candidates = @($candidates | Where-Object { $_.name_label -eq $SrName }) }
    if ($candidates.Count -eq 0) {
        $named = if ($SrName) { " named '$SrName'" } else { "" }
        throw "no SR here can hold the pool metadata${named}: it needs an iSCSI or Fibre Channel SR attached to every host"
    }
    $sr = $candidates[0]

    # The pool's own metadata disk on this SR is what says replication is on (as the Configure DR dialog
    # decides): a disk of type metadata whose metadata_of_pool is this pool.
    $pool = Get-XenPool
    $metadataDisk = {
        Get-XenVDI | Where-Object {
            $_.type -eq 'metadata' -and $_.SR.opaque_ref -eq $sr.opaque_ref -and
            $_.metadata_of_pool.opaque_ref -eq $pool.opaque_ref
        } | Select-Object -First 1
    }

    $wasOn = [bool](& $metadataDisk)
    if ($wasOn) {
        Write-Host "The pool metadata is already replicated to $($sr.name_label)"
    }
    else {
        Write-Host "Replicating the pool metadata to $($sr.name_label)"
        $sr | Invoke-XenSR -XenAction EnableDatabaseReplication
    }

    $vdi = & $metadataDisk
    Write-Host ("  metadata disk: {0} ({1}), {2} MiB, up to date: {3}" -f $vdi.name_label, $vdi.uuid,
        ($vdi.virtual_size / 1MB), $vdi.metadata_latest)

    if (-not $wasOn) {
        # Turning replication off destroys the metadata disk.
        $sr | Invoke-XenSR -XenAction DisableDatabaseReplication
        Write-Host "Turned replication off again, as it was before"
    }
    Write-Host "OK: configure-disaster-recovery"
    $session | Disconnect-XenServer
}
