# Reclaim freed space on a thin SR.
#
# Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable SR, pick
# a host with a live connection to it, and run the trim operation.
#
# Run it:
#   ./workflows.sh reclaim-space https://xenserver root "$password"

reclaim_space() {
    local sr candidate type pbd h name result
    # A thin-provisioned SR (local LVM here) can return space freed by deleted disks to the backend via
    # the trim plugin. Find one via its storage manager's SR_TRIM feature, instead of hard-coding a
    # type.
    sr=""
    for candidate in $(each_csv "$(xe sr-list --minimal)"); do
        type=$(xe sr-param-get uuid=$candidate param-name=type)
        [[ $(xe sm-list type=$type params=features --minimal) == *SR_TRIM* ]] || continue
        [ "$(xe sr-param-get uuid=$candidate param-name=physical-size)" -gt 0 ] || continue
        sr=$candidate; break
    done
    [ -n "$sr" ] || { echo "no trim-capable SR was found" >&2; exit 1; }

    # A host with a live (plugged) connection to the SR runs the plugin.
    pbd=$(first_csv "$(xe pbd-list sr-uuid=$sr currently-attached=true --minimal)")
    h=$(xe pbd-param-get uuid=$pbd param-name=host)
    name=$(xe sr-param-get uuid=$sr param-name=name-label)
    result=$(xe host-call-plugin host-uuid=$h plugin=trim fn=do_trim args:sr_uuid=$sr)
    echo "  reclaimed freed space on $name: $result"
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    [ "${result,,}" = "true" ] || { echo "trim failed: $result" >&2; exit 1; }
    echo "OK: reclaim-space"
}
