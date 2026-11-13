# Small helpers several workflows share: finding objects by name, waiting for the guest agent,
# tidying up what an example created.

function Invoke-XenMethod {
    <#
    .SYNOPSIS
        A thin JSON-RPC caller for the handful of XenAPI methods the module ships no cmdlet for
        (Get-XenEventBatch, in GettingStarted\Invoke-Events.ps1, uses the same pattern).
    .DESCRIPTION
        Pure PowerShell — Connect-Example has already trusted the server's certificate, so no extra TLS
        setup is needed.
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Method,
        # Optional: plenty of methods take nothing but the session (VM.get_all_records, for one), and a
        # mandatory array rejects @() rather than treating it as "no further arguments".
        [object[]]$Params = @()
    )
    $body = @{ jsonrpc = "2.0"; id = 1; method = $Method; params = @($Session.opaque_ref) + $Params } |
        ConvertTo-Json -Depth 6
    $resp = Invoke-RestMethod -Uri "$($Session.Url)/jsonrpc" -Method Post -Body $body -ContentType "application/json"
    if ($resp.error) { throw "$Method failed: $($resp.error | ConvertTo-Json -Compress)" }
    return $resp.result
}

function Invoke-DetachAndForgetSr {
    <#
    .SYNOPSIS
        Detach an SR from every host, then forget it.
    .DESCRIPTION
        Forget refuses an SR that is still attached (SR_HAS_PBD), so unplug its PBDs first. Forgetting
        drops the pool's record of the SR but leaves the data on the storage itself.
    #>
    param([Parameter(Mandatory = $true)]$Ref)
    (Get-XenSR -Ref $Ref).PBDs | ForEach-Object { Get-XenPBD -Ref $_ } |
        Where-Object { $_.currently_attached } |
        ForEach-Object { $_ | Invoke-XenPBD -XenAction Unplug }
    Invoke-XenSR -Ref $Ref -XenAction Forget
}

function Invoke-VmProvision {
    <#
    .SYNOPSIS
        Invoke-XenVM -XenAction Provision, after filling in the SR for every disk the template describes.
    .DESCRIPTION
        A template's other_config["disks"] names each disk's SR as sr="" (empty); a real host takes that
        literally and Provision fails with UUID_INVALID, so point the disks at the pool's default SR first -
        exactly what `xe vm-install` does before calling VM.provision itself.
    #>
    param([Parameter(Mandatory = $true)]$Ref)
    $vm = Get-XenVM -Ref $Ref
    $disks = $vm.other_config["disks"]
    if ($disks -and $disks.Contains('sr=""')) {
        $srUuid = (Get-XenSR -Ref (Get-XenPool | Select-Object -First 1).default_SR).uuid
        # Set-XenVM -OtherConfig replaces the whole map, so copy it and change only "disks".
        $oc = @{}
        foreach ($k in $vm.other_config.Keys) { $oc[$k] = $vm.other_config[$k] }
        $oc["disks"] = $disks.Replace('sr=""', "sr=""$srUuid""")
        $vm | Set-XenVM -OtherConfig $oc
    }
    $vm | Invoke-XenVM -XenAction Provision
}

function Remove-VmAndDisks {
    <#
    .SYNOPSIS
        Destroy a VM (or snapshot, or template) an example made, and the disks it owns.
    .DESCRIPTION
        Remove-XenVM removes only the VM record and leaves its disks behind, so collect them first (from a
        fresh read of the VM: an object from -PassThru may predate its disks) and destroy them afterwards -
        exactly what Invoke-DeleteVm does by hand.
    #>
    param([Parameter(Mandatory = $true)]$Ref)
    $vdis = (Get-XenVM -Ref $Ref).VBDs |
        ForEach-Object { Get-XenVBD -Ref $_ } |
        Where-Object { $_.type -eq 'Disk' -and $_.VDI -ne 'OpaqueRef:NULL' } |
        ForEach-Object { $_.VDI }
    # A checkpoint (or a suspended VM) also owns a suspend image holding its memory, which no VBD points
    # at: destroy that as well.
    $suspendVdi = (Get-XenVM -Ref $Ref).suspend_VDI
    if ($suspendVdi -and $suspendVdi -ne 'OpaqueRef:NULL') { $vdis = @($vdis) + $suspendVdi }
    Remove-XenVM -Ref $Ref
    $vdis | ForEach-Object { Remove-XenVDI -Ref $_ }
}

function Copy-OfGuest {
    <#
    .SYNOPSIS
        A throwaway VM with a working guest OS: a copy of an existing VM that has one.
    .DESCRIPTION
        Suspend, checkpoint, live migration and clean shutdown all need the guest's cooperation: on a
        running VM with no PV drivers xapi refuses them up front with VM_LACKS_FEATURE (a VM freshly cloned
        from a template has no OS at all). So copy a VM that does have an OS and PV drivers, without
        disturbing it: snapshot it (fine while it runs), clone the snapshot - a clone of a snapshot is a
        template - and provision that into an ordinary VM. The snapshot is only needed for the clone, so it
        goes again straight away.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$SourceVmName,
        [Parameter(Mandatory = $true)][string]$NewVmName
    )
    $source = Get-XenVM -Name $SourceVmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $source) { throw "No VM named '$SourceVmName' was found." }
    $snapshot = $source | Invoke-XenVM -XenAction Snapshot -NewName "$NewVmName-source" -PassThru
    $vm = $snapshot | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm
    Remove-VmAndDisks -Ref $snapshot
    return Get-XenVM -Ref $vm
}

function Invoke-Evacuate {
    <#
    .SYNOPSIS
        Evacuate a host over its management network.
    .DESCRIPTION
        Name the network: before SDK 26.21 the cmdlet always calls the newest host.evacuate, and
        with no -Network it sends an empty network, which a real host refuses (PIF_NOT_PRESENT) as soon as
        there is a VM to move.
    #>
    param([Parameter(Mandatory = $true)]$XenHost)
    $network = (Get-XenPIF | Where-Object {
        $_.management -and $_.host -eq $XenHost
    } | Select-Object -First 1).network
    $XenHost | Invoke-XenHost -XenAction Evacuate -Network $network
}

function Wait-GuestAgent {
    <#
    .SYNOPSIS
        Wait, after Start, until the guest's PV drivers have reported in.
    .DESCRIPTION
        xapi only offers the guest-dependent operations once the guest says it can do them, and
        allowed_operations is where it says so: wait for clean_shutdown to appear there (the same check that
        refuses it with VM_LACKS_FEATURE beforehand). A Linux kernel offers that early in boot, before the
        agent runs (hot-plug needs the agent, and suspend needs its emulated disk unplugged), so wait for
        the guest metrics to report the PV drivers too. A booting OS takes a while.
    #>
    param(
        [Parameter(Mandatory = $true)]$Ref,
        [int]$TimeoutSeconds = 300,
        [int]$IntervalSeconds = 2
    )
    $ready = {
        $vm = Get-XenVM -Ref $Ref
        $vm.allowed_operations -contains 'clean_shutdown' -and
            $vm.guest_metrics -ne 'OpaqueRef:NULL' -and
            (Get-XenVMGuestMetrics -Ref $vm.guest_metrics).PV_drivers_detected
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not (& $ready)) {
        if ((Get-Date) -gt $deadline) {
            throw ("the guest's PV drivers did not report in within ${TimeoutSeconds}s; does the " +
                   "source VM have a guest OS with PV drivers (XenServer VM Tools)?")
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
}

function Invoke-ProbeForFailure {
    <#
    .SYNOPSIS
        Return the XML a backend sends back on its deliberately-failing discovery probe.
    .DESCRIPTION
        Discover iSCSI/HBA LUNs by asking with an incomplete device-config on purpose: the backend can't
        create anything from it yet, so it fails with an SR_BACKEND_FAILURE_<n> error whose params carry
        an XML fragment describing what it found (the IQNs on offer, then the LUNs behind one of them, or
        - for HBA - every LUN visible at all). A probe that unexpectedly *succeeds* means the
        device-config was already complete - not the discovery prompt this helper is looking for. (Never
        probe by attempting SR.create instead: on real storage a create that unexpectedly succeeds
        formats the LUN.)
    #>
    param(
        [Parameter(Mandatory = $true)]$XenHostRef,
        [Parameter(Mandatory = $true)][hashtable]$DeviceConfig,
        [Parameter(Mandatory = $true)][string]$SmType
    )
    $succeeded = $false
    try {
        # SR.probe is a static call: the host goes in -XenHost, and -Ref (which the cmdlet insists on) is
        # ignored. Putting the host in -Ref instead sends an empty host, which a real host refuses with
        # HOST_OFFLINE.
        Invoke-XenSR -Ref "OpaqueRef:NULL" -XenAction Probe -XenHost $XenHostRef -DeviceConfig $DeviceConfig `
            -Type $SmType -SmConfig @{} -PassThru | Out-Null
        $succeeded = $true
    }
    catch {
        $ex = $_.Exception
        while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
        if ($ex -and $ex.ErrorDescription) {
            for ($i = $ex.ErrorDescription.Count - 1; $i -ge 0; $i--) {
                $detail = $ex.ErrorDescription[$i]
                if ($detail -and $detail.Trim().StartsWith('<')) { return $detail }
            }
        }
        throw
    }
    if ($succeeded) {
        throw "SR.probe for $SmType succeeded without asking for more information; check the target address"
    }
}

function Enable-WhenBooted {
    <#
    .SYNOPSIS
        Re-enable a host that has just come back.
    .DESCRIPTION
        It reports itself live before xapi on it has finished starting, and until then Enable fails
        HOST_STILL_BOOTING - so retry that.
    #>
    param($XenHost, [int]$TimeoutSeconds = 600, [int]$IntervalSeconds = 10)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        try { $XenHost | Invoke-XenHost -XenAction Enable; return }
        catch {
            $ex = $_.Exception
            while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
            if (-not ($ex -and $ex.ErrorDescription -and $ex.ErrorDescription[0] -eq "HOST_STILL_BOOTING") `
                    -or (Get-Date) -gt $deadline) {
                throw
            }
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
}

function Wait-ForRestart {
    <#
    .SYNOPSIS
        Wait for a host to come back from a reboot (Key "boot_time") or toolstack restart
        ("agent_start_time").
    .DESCRIPTION
        Until that other_config entry differs from -Before and the host is live. Reconnects every time
        round, because the host restarting may be the coordinator this session talks to; returns the new
        session.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$HostUuid,
        [Parameter(Mandatory = $true)][string]$Key,
        $Before,
        [int]$TimeoutSeconds = 1800,
        [int]$IntervalSeconds = 10
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        try {
            $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
            $xenHost = Get-XenHost -Uuid $HostUuid
            if ($xenHost.other_config[$Key] -ne $Before -and (Get-HostLive $xenHost)) { return $session }
            $session | Disconnect-XenServer
        }
        catch {
            # down, or xapi still starting: a connection error or any XenAPI failure, keep retrying.
        }
        if ((Get-Date) -gt $deadline) { throw "host $HostUuid did not come back in time" }
        Start-Sleep -Seconds $IntervalSeconds
    }
}

function Move-DisksToSr {
    <#
    .SYNOPSIS
        Relocate every one of a (not-yet-started) VM's disks onto the given SR, the same VDI PoolMigrate
        storage-migrate already demonstrates; reused here to guarantee a VM's disk lands on a *shared* SR
        before pinning/starting it for an evacuation demo.
    #>
    param([Parameter(Mandatory = $true)]$VmRef, [Parameter(Mandatory = $true)]$SrRef)
    (Get-XenVM -Ref $VmRef).VBDs | ForEach-Object { Get-XenVBD -Ref $_ } |
        Where-Object { $_.type -eq 'Disk' -and $_.VDI -ne 'OpaqueRef:NULL' } |
        ForEach-Object {
            if ((Get-XenVDI -Ref $_.VDI).SR -ne $SrRef) {
                Invoke-XenVDI -Ref $_.VDI -XenAction PoolMigrate -SR $SrRef -Options @{}
            }
        }
}

function New-UpdateRepositories {
    <#
    .SYNOPSIS
        Introduce the pool's update repositories.
    .DESCRIPTION
        The release's base packages (Update=$false) and its update stream (Update=$true, which
        pool.sync_updates needs - otherwise NO_REPOSITORY_ENABLED). A real host checks the URLs
        (INVALID_BASE_URL for an unknown domain), so these are the XenServer CDN's, e.g.
        https://repo.ops.xenserver.com/xs9/{base,normal}.
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )
    return @("base", "normal") | ForEach-Object {
        $stage = $_
        # Repository.introduce is a static-style create, so pass the NULL ref for the (ignored)
        # instance param.
        Invoke-XenRepository -Ref 'OpaqueRef:NULL' -XenAction Introduce -NameLabel "sdk-example-$stage" `
            -NameDescription "SDK example $stage repository" -BinaryUrl "$RepoUrl/$stage" `
            -SourceUrl "$SourceUrl/$stage" -Update ($stage -ne "base") -GpgkeyPath '' -PassThru
    }
}

function Get-HostLive {
    param($XenHost)
    (Get-XenHostMetrics -Ref (Get-XenHost -Ref $XenHost).metrics).live
}
