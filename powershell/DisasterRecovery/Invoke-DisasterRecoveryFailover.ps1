function Invoke-DisasterRecoveryFailover {
    <#
    .SYNOPSIS
        Fail over to the disaster recovery site.
    .DESCRIPTION
        On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's
        storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes. By
        default this is a test failover, which removes what it recovered and detaches the storage again.
    .EXAMPLE
        Invoke-DisasterRecoveryFailover -Url https://dr-site-pool -UserName root -Password $password `
            -Target 192.0.2.31 -TargetIqn iqn.2009-01.com.example:replica-0 -ScsiId 360a98...
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$Target,
        [string]$TargetIqn,
        [Parameter(Mandatory = $true)][string]$ScsiId,
        [string]$Port,
        [string]$SrType = 'lvmoiscsi',
        [bool]$TestFailover = $true
    )
    # The replica is the LUN the storage array mirrors the protected pool's SR to: name it by the iSCSI
    # target, IQN and SCSI id (SrType lvmoiscsi), or by SCSI id alone for Fibre Channel/SAS (SrType
    # lvmohba). Before a real failover, break the mirror so that this site can write to the replica, and
    # make sure no other pool has those LUNs attached: two pools using the same LUN corrupt it.
    #
    # DR_task.create attaches every SR on the LUN that you name (by uuid) to this pool, keeping its uuid,
    # and VDI.open_database gives a session onto the metadata replicated there - a separate, read-only
    # database, not this pool. Recovering runs on that session and names this pool's session as the place
    # to recover into. A test failover then removes the recovered VMs and vApps - not their disks, which
    # are the replica's - and detaches and forgets the SRs, as the wizard does.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $deviceConfig = @{ SCSIid = $ScsiId }
    if ($SrType -eq 'lvmoiscsi') {
        $deviceConfig.target = $Target
        $deviceConfig.targetIQN = $TargetIqn
        if ($Port) { $deviceConfig.port = $Port }
    }

    # Which SRs are on the LUN, and which of them hold pool metadata. sm_config metadata=true asks for
    # their names and the pool_metadata_detected flag as well as their uuids. (SR.probe is a static call:
    # the host goes in -XenHost, and -Ref, which the cmdlet insists on, is ignored.)
    $master = (Get-XenPool).master.opaque_ref
    $probe = Invoke-XenSR -Ref "OpaqueRef:NULL" -XenAction Probe -XenHost $master -DeviceConfig $deviceConfig `
        -Type $SrType -SmConfig @{ metadata = 'true' } -PassThru
    $srs = @(([xml]$probe).SelectNodes('/SRlist/SR'))
    foreach ($found in $srs) {
        $withMetadata = if ("$($found.pool_metadata_detected)".Trim() -eq 'true') { ", with pool metadata" } else { "" }
        Write-Host "Found SR $("$($found.name_label)".Trim()) ($("$($found.UUID)".Trim()))$withMetadata"
    }
    if ($srs.Count -eq 0) { throw "there is no SR on that LUN" }

    $task = New-XenDRTask -Type $SrType -DeviceConfig $deviceConfig `
        -Whitelist @($srs | ForEach-Object { "$($_.UUID)".Trim() }) -PassThru
    $introduced = @($task.introduced_SRs | ForEach-Object { Get-XenSR -Ref $_.opaque_ref })
    Write-Host "Attached $(($introduced | ForEach-Object { $_.name_label }) -join ', ')"

    # Recover from every replicated database on the attached SRs: vApps first (their VMs come with them),
    # then the VMs not in a vApp. A VM whose disks are on storage this pool hasn't attached can't be
    # recovered - assert_can_be_recovered says so (VM_REQUIRES_SR) - so skip it.
    #
    # The module's cmdlets only take sessions they created themselves, so the calls on the replicated
    # database go over JSON-RPC (Invoke-XenMethod, in Helpers.ps1).
    $recoveredVms = @()
    $recoveredVapps = @()
    foreach ($sr in $introduced) {
        $vdis = Get-XenVDI | Where-Object {
            $_.SR.opaque_ref -eq $sr.opaque_ref -and $_.type -eq 'metadata' -and $_.metadata_latest
        }
        foreach ($vdi in $vdis) {
            $databaseRef = Invoke-XenMethod -Session $session -Method 'VDI.open_database' -Params @($vdi.opaque_ref)
            $database = [pscustomobject]@{ opaque_ref = $databaseRef; Url = $session.Url }

            # A pool often has no name of its own; show its coordinator's name instead.
            $pool = (Invoke-XenMethod -Session $database -Method 'pool.get_all_records').PSObject.Properties |
                Select-Object -First 1
            $poolName = $pool.Value.name_label
            if (-not $poolName) {
                $poolName = Invoke-XenMethod -Session $database -Method 'host.get_name_label' -Params @($pool.Value.master)
            }
            Write-Host "  pool metadata of $poolName"

            $inRecoveredVapp = @{}
            $vapps = (Invoke-XenMethod -Session $database -Method 'VM_appliance.get_all_records').PSObject.Properties
            foreach ($vapp in $vapps) {
                try {
                    Invoke-XenMethod -Session $database -Method 'VM_appliance.assert_can_be_recovered' `
                        -Params @($vapp.Name, $session.opaque_ref) | Out-Null
                }
                catch {
                    Write-Host "  cannot recover vApp $($vapp.Value.name_label): $(Get-FailureCode $_)"
                    continue
                }
                Invoke-XenMethod -Session $database -Method 'VM_appliance.recover' `
                    -Params @($vapp.Name, $session.opaque_ref, $false) | Out-Null
                $recoveredVapps += $vapp.Value.uuid
                foreach ($vm in $vapp.Value.VMs) {
                    $recoveredVms += Invoke-XenMethod -Session $database -Method 'VM.get_uuid' -Params @($vm)
                    $inRecoveredVapp[$vm] = $true
                }
                Write-Host "  recovered vApp $($vapp.Value.name_label)"
            }

            $vms = (Invoke-XenMethod -Session $database -Method 'VM.get_all_records').PSObject.Properties |
                Sort-Object { $_.Value.name_label }
            foreach ($vm in $vms) {
                $r = $vm.Value
                if ($r.is_a_template -or $r.is_control_domain -or $r.is_a_snapshot -or $inRecoveredVapp[$vm.Name]) {
                    continue
                }
                try {
                    Invoke-XenMethod -Session $database -Method 'VM.assert_can_be_recovered' `
                        -Params @($vm.Name, $session.opaque_ref) | Out-Null
                }
                catch {
                    Write-Host "  cannot recover $($r.name_label): $(Get-FailureCode $_)"
                    continue
                }
                Invoke-XenMethod -Session $database -Method 'VM.recover' `
                    -Params @($vm.Name, $session.opaque_ref, $false) | Out-Null
                $recoveredVms += $r.uuid
                Write-Host "  recovered $($r.name_label)"
            }
            Invoke-XenMethod -Session $database -Method 'session.logout' | Out-Null
        }
    }

    # The recovered VMs keep their uuids, so look them up by uuid - a name may be taken here already.
    foreach ($uuid in $recoveredVms) {
        $vm = Get-XenVM -Uuid $uuid
        Write-Host "$($vm.name_label) is $($vm.power_state)"
    }

    if ($TestFailover) {
        foreach ($uuid in $recoveredVms) {
            $vm = Get-XenVM -Uuid $uuid
            if ($vm.power_state -ne 'Halted') { $vm | Invoke-XenVM -XenAction HardShutdown }
            $vm | Remove-XenVM
        }
        foreach ($uuid in $recoveredVapps) { Get-XenVMAppliance -Uuid $uuid | Remove-XenVMAppliance }
    }
    # Destroying the task detaches and forgets the SRs it attached that no recovered VM needs.
    $task | Remove-XenDRTask
    if ($TestFailover) {
        # The SRs the recovered VMs needed are no longer the task's: detach and forget those too.
        foreach ($sr in $introduced) {
            if (Get-XenSR -Uuid $sr.uuid -ErrorAction SilentlyContinue) {
                Invoke-DetachAndForgetSr -Ref $sr.opaque_ref
            }
        }
        Write-Host "Test failover: removed the recovered VMs and detached the replica"
    }
    else {
        Write-Host "Recovered VMs are halted: start them when you are ready"
    }
    Write-Host "OK: disaster-recovery-failover"
    $session | Disconnect-XenServer
}

function Get-FailureCode {
    <#
    .SYNOPSIS
        The XenAPI error code in a failed Invoke-XenMethod call.
    #>
    param($ErrorRecord)
    if ("$ErrorRecord" -match '"message":"([A-Z0-9_]+)"') { return $Matches[1] }
    return "$ErrorRecord"
}
