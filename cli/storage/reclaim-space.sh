# Reclaim freed space on a thin SR.
#
# Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable SR, pick
# a host with a live connection to it, and run the trim operation.
#
# Run it:
#   ./workflows.sh reclaim-space https://xenserver root "$password"

reclaim_space() {
    local sr candidate type pbd h name result size before after
    # A thin-provisioned SR (local LVM here) can return space freed by deleted disks to the backend via
    # the trim plugin. Find one via its storage manager's SR_TRIM feature, instead of hard-coding a
    # type.
    sr=""
    for candidate in $(each_csv "$(remote_xe sr-list --minimal)"); do
        type=$(remote_xe sr-param-get uuid=$candidate param-name=type)
        [[ $(remote_xe sm-list type=$type params=features --minimal) == *SR_TRIM* ]] || continue
        [ "$(remote_xe sr-param-get uuid=$candidate param-name=physical-size)" -gt 0 ] || continue
        sr=$candidate; break
    done
    [ -n "$sr" ] || { echo "no trim-capable SR was found" >&2; exit 1; }

    # A host with a live (plugged) connection to the SR runs the plugin.
    pbd=$(first_csv "$(remote_xe pbd-list sr-uuid=$sr currently-attached=true --minimal)")
    h=$(remote_xe pbd-param-get uuid=$pbd param-name=host)
    name=$(remote_xe sr-param-get uuid=$sr param-name=name-label)
    size=$(remote_xe sr-param-get uuid=$sr param-name=physical-size)
    before=$(remote_xe sr-param-get uuid=$sr param-name=physical-utilisation)
    echo "  $name: $((before / 1073741824)) / $((size / 1073741824)) GiB used"

    result=$(remote_xe host-call-plugin host-uuid=$h plugin=trim fn=do_trim args:sr_uuid=$sr)
    echo "  reclaimed freed space on $name: $result"
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    [ "${result,,}" = "true" ] || { echo "trim failed: $result" >&2; exit 1; }

    # Rescan to refresh utilisation from the backend, the same way sr-usage does, before reporting it.
    remote_xe sr-scan uuid=$sr
    after=$(remote_xe sr-param-get uuid=$sr param-name=physical-utilisation)
    echo "  $name: $((after / 1073741824)) / $((size / 1073741824)) GiB used"
    ok reclaim-space
}
