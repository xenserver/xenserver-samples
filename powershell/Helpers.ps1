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
        Wait, after Start, until the guest's PV drivers have reported in, then settle.
    .DESCRIPTION
        xapi only offers the guest-dependent operations once the guest says it can do them, and
        allowed_operations is where it says so: wait for clean_shutdown to appear there (the same check that
        refuses it with VM_LACKS_FEATURE beforehand). A Linux kernel offers that early in boot, before the
        agent runs (hot-plug needs the agent, and suspend needs its emulated disk unplugged), so wait for
        the guest metrics to report the PV drivers too. A booting OS takes a while.

        Even then the guest may still be booting, and a guest asked to suspend mid-boot (suspend, checkpoint,
        live migration) can fail to freeze a process that is busy starting up: it then abandons the suspend
        without telling the host, which waits until VM_SUSPEND_TIMEOUT. xapi has no "boot finished" signal,
        so also wait for the guest to report an IP address - a sign it has finished booting, when it has a
        network - but that is only best effort: a guest with no network (no NIC, DHCP failure, an isolated
        network) has still booted, so a missing IP address by the deadline is not a failure.
    #>
    param(
        [Parameter(Mandatory = $true)]$Ref,
        [int]$TimeoutSeconds = 300,
        [int]$IntervalSeconds = 2,
        [int]$SettleSeconds = 30
    )
    $ready = {
        $vm = Get-XenVM -Ref $Ref
        $vm.allowed_operations -contains 'clean_shutdown' -and
            $vm.guest_metrics -ne 'OpaqueRef:NULL' -and
            (Get-XenVMGuestMetrics -Ref $vm.guest_metrics).PV_drivers_detected
    }
    $hasIp = {
        $vm = Get-XenVM -Ref $Ref
        $vm.guest_metrics -ne 'OpaqueRef:NULL' -and
            @((Get-XenVMGuestMetrics -Ref $vm.guest_metrics).networks.Keys |
                Where-Object { $_ -like '*/ip' -or $_ -like '*/ipv4/*' }).Count -gt 0
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not (& $ready)) {
        if ((Get-Date) -gt $deadline) {
            throw ("the guest did not finish booting (PV drivers) within " +
                   "${TimeoutSeconds}s; does the source VM have a guest OS with PV drivers (XenServer VM Tools)?")
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
    while (-not (& $hasIp)) {
        if ((Get-Date) -gt $deadline) {
            Write-Host "  no IP address reported within ${TimeoutSeconds}s; carrying on (the guest has no network address)"
            break
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
    Start-Sleep -Seconds $SettleSeconds
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

function Invoke-HostUpdate {
    <#
    .SYNOPSIS
        Apply the pool's synced updates to one host, act on whatever guidance that leaves pending,
        and return the host to service. Shared by Invoke-ApplyUpdate, which updates one host, and
        Invoke-RollingPoolUpdate, which updates them all.
    .DESCRIPTION
        ApplyUpdates refuses a batch whose mandatory guidance needs an evacuation with
        HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs are moved off first - handle that
        rather than assuming an update batch never asks for one: disable the host, evacuate it, and
        apply again. Stay disabled afterwards - xapi refuses Reboot on an enabled host
        (HOST_NOT_DISABLED) - Enable-WhenBooted below returns the host to service once it is back,
        whether or not it needed a restart at all. Then read the host's pending_guidances: a reboot
        or a toolstack restart returns before it has actually happened, and if this host is the
        coordinator a reboot takes -Session with it - so note when the host last started, ask for the
        restart, and reconnect (Wait-ForRestart) until it reports a newer start and is live again.
        Resolve any pending mandatory host guidance before returning - leaving it would otherwise
        block the next ApplyUpdates on this host with HOST_PENDING_MANDATORY_GUIDANCES_NOT_EMPTY.
        Guidance that targets VMs instead of hosts (for example restarting a VM) is not handled here.

        -Label prefixes the progress lines this prints, e.g. the host's name followed by ": ".

        Returns the session to keep using from here on - the same one, unless a restart replaced it.
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)]$XenHost,
        [Parameter(Mandatory = $true)]$Hash,
        [string]$Label = ""
    )
    try {
        $XenHost | Invoke-XenHost -XenAction ApplyUpdates -Hash $Hash
    }
    catch {
        $ex = $_.Exception
        while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
        if (-not ($ex -and $ex.ErrorDescription -and $ex.ErrorDescription[0] -eq "HOST_EVACUATION_IS_REQUIRED")) {
            throw
        }
        Write-Host "  ${Label}needs evacuating first; evacuating and retrying"
        $XenHost | Invoke-XenHost -XenAction Disable
        Invoke-Evacuate -XenHost $XenHost
        $XenHost | Invoke-XenHost -XenAction ApplyUpdates -Hash $Hash
        # Stay disabled: xapi refuses Reboot on an enabled host (HOST_NOT_DISABLED), and
        # Enable-WhenBooted below returns the host to service once it is back.
    }
    $guidance = @((Get-XenHost -Ref $XenHost).pending_guidances)
    Write-Host "  ${Label}applied; pending guidance = [$($guidance -join ', ')]"
    if ($guidance -contains "reboot_host" -or $guidance -contains "restart_toolstack") {
        # Either restart returns before it has happened, and if this host is the coordinator it
        # takes this session with it - so note when the host last started, restart it, and
        # reconnect until it reports a newer start and is live again.
        $key = if ($guidance -contains "reboot_host") { "boot_time" } else { "agent_start_time" }
        $before = (Get-XenHost -Ref $XenHost).other_config[$key]
        if ($key -eq "boot_time") {
            $XenHost | Invoke-XenHost -XenAction Reboot
        }
        else {
            $XenHost | Invoke-XenHost -XenAction RestartAgent
        }
        $Session = Wait-ForRestart -Url $Url -UserName $UserName -Password $Password `
            -HostUuid $XenHost.uuid -Key $key -Before $before
    }
    # ApplyUpdates disables the host while it works (auto_enable: a restart puts it back) - with no
    # restart to do, nothing re-enables it. Return it to service either way.
    Enable-WhenBooted -XenHost $XenHost
    return $Session
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

function New-UpdateRepository {
    <#
    .SYNOPSIS
        Introduce the pool's update repository.
    .DESCRIPTION
        The release's update stream (Update=$true, which pool.sync_updates needs - otherwise
        NO_REPOSITORY_ENABLED). A real host checks the URL (INVALID_BASE_URL for an unknown domain),
        so this is the XenServer CDN's, e.g. https://repo.ops.xenserver.com/xs9/normal.
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )
    # Repository.introduce is a static-style create, so pass the NULL ref for the (ignored)
    # instance param.
    return Invoke-XenRepository -Ref 'OpaqueRef:NULL' -XenAction Introduce `
        -NameLabel "sdk-example-normal" -NameDescription "SDK example update repository" `
        -BinaryUrl "$RepoUrl/normal" -SourceUrl "$SourceUrl/normal" -Update $true -GpgkeyPath '' -PassThru
}

function Assert-HaAndWlbOff {
    <#
    .SYNOPSIS
        Stop if High Availability or Workload Balancing is on.
    .DESCRIPTION
        ApplyUpdates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
        Workload Balancing to be switched off before you start updating - so check both up front and
        stop rather than disabling either for you; turn them back on again once the update is done.
    #>
    param([Parameter(Mandatory = $true)]$Pool)
    if ($Pool.ha_enabled -or $Pool.wlb_enabled) {
        throw "HA and Workload Balancing must both be off before updating the pool; disable them, " +
            "run this again, then re-enable them once it finishes"
    }
}

function Connect-UpdateRepository {
    <#
    .SYNOPSIS
        Get the pool ready to sync updates from -RepoUrl.
    .DESCRIPTION
        Check that HA and Workload Balancing are off (Assert-HaAndWlbOff), then introduce the update
        repository and make it the pool's only one. Returns the repository and the pool's previous
        repositories, for Disconnect-UpdateRepository to put back.

        pool.sync_updates needs at least one repository with Update enabled (NO_REPOSITORY_ENABLED
        otherwise).
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)]$Pool,
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )
    Assert-HaAndWlbOff -Pool $Pool
    $repo = New-UpdateRepository -Session $Session -RepoUrl $RepoUrl -SourceUrl $SourceUrl
    $previous = @((Get-XenPool -Ref $Pool).repositories)
    try {
        $Pool | Set-XenPool -Repositories @($repo)
    }
    catch {
        $repo | Invoke-XenRepository -XenAction Forget
        throw
    }
    return [pscustomobject]@{ Repository = $repo; Previous = $previous }
}

function Disconnect-UpdateRepository {
    <#
    .SYNOPSIS
        Undo Connect-UpdateRepository: give the pool back its previous repositories and forget the one
        it introduced.
    #>
    param([Parameter(Mandatory = $true)]$Pool, [Parameter(Mandatory = $true)]$Attached)
    $Pool | Set-XenPool -Repositories $Attached.Previous
    $Attached.Repository | Invoke-XenRepository -XenAction Forget
}

function Test-RealVM {
    <#
    .SYNOPSIS
        Whether a VM is a guest: not a template, a snapshot or a host's control domain.
    #>
    param([Parameter(Mandatory = $true)]$VM)
    -not ($VM.is_a_template -or $VM.is_a_snapshot -or $VM.is_control_domain)
}

function Assert-NoPendingGuidance {
    <#
    .SYNOPSIS
        Stop before updating if a host or VM still has mandatory guidance pending from an earlier update.
    .DESCRIPTION
        ApplyUpdates refuses a host that has some (HOST_PENDING_MANDATORY_GUIDANCES_NOT_EMPTY), part-way
        through the update otherwise: act on it first - restart the host, its toolstack or the VM - and run
        the update again.
    #>
    $objects = @(Get-XenHost) + @(Get-XenVM | Where-Object { Test-RealVM -VM $_ })
    $pending = @($objects | Where-Object { $_.pending_guidances.Count -gt 0 } |
        ForEach-Object { "$($_.name_label): $($_.pending_guidances -join ', ')" } | Sort-Object)
    if ($pending.Count -gt 0) {
        throw "an earlier update's guidance is still pending - act on it first: $($pending -join '; ')"
    }
}

function Assert-HostsCanBeEvacuated {
    <#
    .SYNOPSIS
        Stop before changing anything if a host's VMs could not all move to another host.
    .DESCRIPTION
        VmsWhichPreventEvacuation names them (for example a VM with a disk on the host's local storage, or
        a pool with nowhere else to put them).
    #>
    param([Parameter(Mandatory = $true)]$Hosts)
    foreach ($xenHost in $Hosts) {
        $blocking = Get-XenHostProperty -XenHost $xenHost -XenProperty VmsWhichPreventEvacuation
        if ($blocking.Count -gt 0) {
            $names = ($blocking.Keys | ForEach-Object { (Get-XenVM -Ref $_).name_label }) -join ', '
            throw "$($xenHost.name_label) cannot be evacuated: move or shut down $names first"
        }
    }
}

function Get-HostsCoordinatorFirst {
    <#
    .SYNOPSIS
        The pool's hosts, coordinator first: the update documentation asks for the coordinator to be
        updated before any other host.
    #>
    $pool = Get-XenPool | Select-Object -First 1
    @(Get-XenHost -Ref $pool.master) + @(Get-XenHost | Where-Object { $pool.master -ne $_ })
}

function Update-Hosts {
    <#
    .SYNOPSIS
        Apply the synced updates (-Hash) to each host in turn, keeping the VMs running.
    .DESCRIPTION
        Disable the host so nothing new starts there, evacuate it (live-migrating its VMs to the other
        hosts), and let Invoke-HostUpdate apply the updates, restart the host or its toolstack if the
        update asks for that, and enable it again. The VMs stay where evacuation put them. Returns the
        session to keep using from here on - a restart of the coordinator replaces it.
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)]$Hosts,
        [Parameter(Mandatory = $true)][string]$Hash
    )
    foreach ($xenHost in $Hosts) {
        Write-Host "Updating $($xenHost.name_label): moving its VMs to the rest of the pool"
        $xenHost | Invoke-XenHost -XenAction Disable
        Invoke-Evacuate -XenHost $xenHost
        $Session = Invoke-HostUpdate -Session $Session -Url $Url -UserName $UserName -Password $Password `
            -XenHost $xenHost -Hash $Hash
    }
    return $Session
}

function Write-VmGuidance {
    <#
    .SYNOPSIS
        Print the guidance updating left pending for VMs - restart_vm or restart_device_model, for a VM to
        start using what was updated.
    .DESCRIPTION
        Acting on it restarts the VM, which is its owner's call rather than the update's, so this only
        reports it.
    #>
    $pending = @(Get-XenVM | Where-Object { (Test-RealVM -VM $_) -and $_.pending_guidances.Count -gt 0 } |
        ForEach-Object { "$($_.name_label): $($_.pending_guidances -join ', ')" } | Sort-Object)
    $text = if ($pending.Count -gt 0) { $pending -join '; ' } else { 'none' }
    Write-Host "VM guidance pending: $text"
}

function Get-HostLive {
    param($XenHost)
    (Get-XenHostMetrics -Ref (Get-XenHost -Ref $XenHost).metrics).live
}

function Get-HostUrl {
    <#
    .SYNOPSIS
        Build the URL for a given host's own address, keeping the scheme and port the caller originally
        connected with (a host's management address carries no port of its own).
    .DESCRIPTION
        Needed anywhere a workflow does raw HTTP against a SPECIFIC host rather than the pool's
        connection URL - a host answers a direct HTTP request only for itself, with no forwarding to
        another pool member.
    #>
    param([string]$Url, [string]$Address)
    $uri = [System.Uri]$Url
    $port = if ($uri.Port -gt 0) { ":$($uri.Port)" } else { "" }
    return "$($uri.Scheme)://$Address$port"
}

function Save-HttpTransfer {
    <#
    .SYNOPSIS
        Download an HTTP transfer (an export, a report) to a file, streamed.
    .DESCRIPTION
        Windows PowerShell 5.1 redraws Invoke-WebRequest's progress bar for every block it writes, which
        makes a download of gigabytes crawl, so the bar is off for this call.
    #>
    param([string]$Uri, [string]$Path)
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing
}

function Send-HttpTransfer {
    <#
    .SYNOPSIS
        Upload a file as an HTTP transfer (an import), streamed.
    .DESCRIPTION
        PowerShell 7's Invoke-WebRequest -InFile streams the file. Windows PowerShell 5.1's reads all of it
        into memory before sending (its request buffers the body), which a VM export of gigabytes doesn't
        fit in, so there the file goes through HttpWebRequest with buffering off - still trusting the
        certificate Connect-Example accepted.
    #>
    param([string]$Uri, [string]$Path, [string]$Method = 'PUT')
    $ProgressPreference = 'SilentlyContinue'
    if ($PSVersionTable.PSEdition -eq 'Core') {
        Invoke-WebRequest -Uri $Uri -Method $Method -InFile $Path -UseBasicParsing | Out-Null
        return
    }
    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = $Method.ToUpperInvariant()
    $request.AllowWriteStreamBuffering = $false
    $request.ContentLength = (Get-Item $Path).Length
    $request.Timeout = [System.Threading.Timeout]::Infinite
    $request.ReadWriteTimeout = [System.Threading.Timeout]::Infinite
    $file = [System.IO.File]::OpenRead($Path)
    try {
        $body = $request.GetRequestStream()
        try { $file.CopyTo($body, 1MB) }
        finally { $body.Dispose() }
    }
    finally { $file.Dispose() }
    # An HTTP error status throws here, as Invoke-WebRequest does.
    $request.GetResponse().Dispose()
}
