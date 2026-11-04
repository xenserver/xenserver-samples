# Restart a host.
#
# Take a host down and bring it back: stop it accepting new VMs, move the ones it is running elsewhere, reboot
# it, then power it right off and back on again.
#
# Run it:
#   ./workflows.sh restart-host https://xenserver root "$password"

restart_host() {
    # Rebooting a host is never just the reboot: anything running on it has to go somewhere first, and the
    # host has to stop accepting new VMs while that happens.
    #
    # Not the coordinator: it is the host xe is talking to, and taking it down would drop the connection
    # underneath the rest of the example.
    pool=$(first_csv "$(xe pool-list --minimal)")
    coordinator=$(xe pool-param-get uuid=$pool param-name=master)
    target=""
    for h in $(each_csv "$(xe host-list --minimal)"); do
        if [ "$h" != "$coordinator" ]; then target=$h; break; fi
    done
    echo "Restarting $(xe host-param-get uuid=$target param-name=name-label)"
    echo "  enabled=$(xe host-param-get uuid=$target param-name=enabled), guests=$(count_host_guest $target)"

    # Disabled means "accept no new VMs"; it does not move anything on its own.
    xe host-disable uuid=$target
    echo "  disabled:   enabled=$(xe host-param-get uuid=$target param-name=enabled)"

    # Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain - the host's own
    # management VM, which cannot move - is left.
    xe host-evacuate uuid=$target
    echo "  evacuated:  guests=$(count_host_guest $target)"

    xe host-reboot uuid=$target
    # A real reboot takes minutes. Wait for the host to drop out and come back (live in its
    # host-metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
    # itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
    # never does - so enable it explicitly rather than depend on either.
    wait_for_host_live "$target" false 600
    wait_for_host_live "$target" true 1200 10
    enable_when_booted "$target"
    echo "  rebooted, re-enabled: enabled=$(xe host-param-get uuid=$target param-name=enabled)"

    # The other ending: off, and back on out of band - but only demonstrated if that is actually
    # configured (host-power-on has no fallback and simply fails if no mechanism is configured or
    # working), and waiting for each transition before starting the next.
    if [ -n "$(xe host-param-get uuid=$target param-name=power-on-mode)" ]; then
        xe host-disable uuid=$target
        xe host-shutdown uuid=$target
        wait_for_host_live "$target" false
        echo "  shut down:  live=$(host_live $target)"
        xe host-power-on uuid=$target
        wait_for_host_live "$target" true 1200 10
        echo "  powered on: live=$(host_live $target)"
        enable_when_booted "$target"
        echo "  re-enabled: enabled=$(xe host-param-get uuid=$target param-name=enabled)"
    else
        echo "  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host"
    fi
    echo "OK: restart-host"
}

# Poll host_metrics.live until it matches, rather than issuing the next power command immediately - real
# out-of-band power control has no retry of its own, so a script that doesn't wait can issue a second
# command while the first is still in flight.
wait_for_host_live() {
    local h=$1 want=$2 timeout=${3:-60} interval=${4:-2}
    local deadline=$((SECONDS + timeout))
    while [ "$(host_live "$h")" != "$want" ]; do
        if [ $SECONDS -gt $deadline ]; then
            echo "host did not reach live=$want in time" >&2
            return 1
        fi
        sleep "$interval"
    done
}

# Resident VMs excluding the control domain, which never moves.
count_host_guest() {
    local n=0
    for vm in $(each_csv "$(set_to_csv "$(xe host-param-get uuid=$1 param-name=resident-VMs)")"); do
        if [ "$(xe vm-param-get uuid=$vm param-name=is-control-domain)" != "true" ]; then n=$((n + 1)); fi
    done
    echo $n
}
