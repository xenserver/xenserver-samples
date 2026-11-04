# Manage SSH access.
#
# Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it again — the
# pool-level call fans out to every host.
#
# Run it:
#   ./workflows.sh manage-ssh-access https://xenserver root "$password"

manage_ssh_access() {
    # Timed access is the point: set the timeout first and the server stamps an expiry when SSH is
    # enabled, so a window opened for troubleshooting closes itself. pool.set_ssh_enabled_timeout is
    # itself a pool-wide fan-out call (exactly like enable_ssh/disable_ssh below), but unlike those two,
    # xe has no CLI command for it at all - only the per-host field is reachable from the CLI - so the
    # host loop here is the only way to do this through xe, not a simplification the SDK languages need.
    # Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
    local before=""
    for h in $(each_csv "$(xe host-list --minimal)"); do
        before="$before $h:$(xe host-param-get uuid=$h param-name=ssh-enabled):$(xe host-param-get uuid=$h param-name=ssh-enabled-timeout)"
        xe host-param-set uuid=$h ssh-enabled-timeout=3600
    done

    # The pool command fans out to every host, so there is no need to loop for the enable itself.
    xe pool-enable-ssh
    for h in $(each_csv "$(xe host-list --minimal)"); do
        echo "$(xe host-param-get uuid=$h param-name=name-label): ssh enabled=$(xe host-param-get uuid=$h param-name=ssh-enabled), expires $(xe host-param-get uuid=$h param-name=ssh-expiry)"
    done

    xe pool-disable-ssh
    states=""
    for h in $(each_csv "$(xe host-list --minimal)"); do
        [ -n "$states" ] && states="$states, "
        states="$states$(xe host-param-get uuid=$h param-name=name-label)=$(xe host-param-get uuid=$h param-name=ssh-enabled)"
    done
    echo "After disable: $states"

    local entry h enabled timeout
    for entry in $before; do
        IFS=: read -r h enabled timeout <<< "$entry"
        xe host-param-set uuid=$h ssh-enabled-timeout=$timeout   # first: enabling stamps the expiry from it
        [ "$enabled" = true ] && xe host-enable-ssh uuid=$h
    done
    echo "OK: manage-ssh-access"
}
