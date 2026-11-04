function Invoke-RestartHost {
    <#
    .SYNOPSIS
        Restart a host.
    .DESCRIPTION
        Take a host down and bring it back: stop it accepting new VMs, move the ones it is running
        elsewhere, reboot it, then power it right off and back on again.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # Rebooting a host is never just the reboot: anything running on it has to go somewhere first, and the
    # host has to stop accepting new VMs while that happens.
    #
    # Not the coordinator: it is the host this session is talking to, and taking it down would drop the
    # connection underneath the rest of the example.
    $pool = Get-XenPool | Select-Object -First 1
    $xenHost = Get-XenHost | Where-Object { $_.opaque_ref -ne $pool.master.opaque_ref } | Select-Object -First 1
    Write-Host "Restarting $($xenHost.name_label)"
    Write-Host "  enabled=$($xenHost.enabled), guests=$(Measure-HostGuest $xenHost)"

    # Disabled means "accept no new VMs"; it does not move anything on its own.
    $xenHost | Invoke-XenHost -XenAction Disable
    Write-Host "  disabled:   enabled=$((Get-XenHost -Ref $xenHost.opaque_ref).enabled)"

    # Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain - the host's own
    # management VM, which cannot move - is left.
    Invoke-Evacuate -XenHost $xenHost
    Write-Host "  evacuated:  guests=$(Measure-HostGuest $xenHost)"

    $xenHost | Invoke-XenHost -XenAction Reboot
    # A real reboot takes minutes. Wait for the host to drop out and come back (live in its
    # host_metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
    # itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
    # never does - so enable it explicitly rather than depend on either.
    Wait-HostLive -XenHost $xenHost -Want $false -TimeoutSeconds 600
    Wait-HostLive -XenHost $xenHost -Want $true -TimeoutSeconds 1200 -IntervalSeconds 10
    Enable-WhenBooted -XenHost $xenHost
    Write-Host "  rebooted, re-enabled: enabled=$((Get-XenHost -Ref $xenHost.opaque_ref).enabled)"

    # The other ending: off, and back on out of band - but only demonstrated if that is actually
    # configured, and waiting for each transition before starting the next: host.power_on has no retry
    # of its own and simply fails, "The host failed to power on.", if no mechanism is configured or
    # working.
    if ((Get-XenHost -Ref $xenHost.opaque_ref).power_on_mode) {
        $xenHost | Invoke-XenHost -XenAction Disable
        $xenHost | Invoke-XenHost -XenAction Shutdown
        Wait-HostLive -XenHost $xenHost -Want $false
        Write-Host "  shut down:  live=$(Get-HostLive $xenHost)"
        $xenHost | Invoke-XenHost -XenAction PowerOn
        Wait-HostLive -XenHost $xenHost -Want $true -TimeoutSeconds 1200 -IntervalSeconds 10
        Write-Host "  powered on: live=$(Get-HostLive $xenHost)"
        Enable-WhenBooted -XenHost $xenHost
        Write-Host "  re-enabled: enabled=$((Get-XenHost -Ref $xenHost.opaque_ref).enabled)"
    }
    else {
        Write-Host "  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host"
    }

    Write-Host "OK: restart-host"
    $session | Disconnect-XenServer
}

function Measure-HostGuest {
    <#
    .SYNOPSIS
        Resident VMs excluding the control domain, which never moves.
    #>
    param($XenHost)
    @((Get-XenHost -Ref $XenHost.opaque_ref).resident_VMs |
        Where-Object { -not (Get-XenVM -Ref $_.opaque_ref).is_control_domain }).Count
}

function Wait-HostLive {
    <#
    .SYNOPSIS
        Poll host_metrics.live until it matches, rather than issuing the next power command immediately -
        real out-of-band power control has no retry of its own, so a tool that doesn't wait can issue a
        second command while the first is still in flight.
    #>
    param($XenHost, [bool]$Want, [int]$TimeoutSeconds = 60, [int]$IntervalSeconds = 2)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-HostLive $XenHost) -ne $Want) {
        if ((Get-Date) -gt $deadline) { throw "host did not reach live=$Want in time" }
        Start-Sleep -Seconds $IntervalSeconds
    }
}
