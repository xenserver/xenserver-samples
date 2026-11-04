# Reclaim freed space on a thin SR.
#
# Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable SR, pick
# a host with a live connection to it, and run the trim operation.
#
# Run it:
#   ./workflows.sh reclaim-space https://xenserver root "$password"

reclaim_space() {
    # A thin-provisioned SR (local LVM here) can return space freed by deleted disks to the backend
    # via the trim plugin - XenCenter's "Reclaim freed space".
    sr=$(first_csv "$(xe sr-list type=lvm --minimal)")
    # A host with a live (plugged) connection to the SR runs the plugin.
    pbd=$(first_csv "$(set_to_csv "$(xe sr-param-get uuid=$sr param-name=PBDs)")")
    h=$(xe pbd-param-get uuid=$pbd param-name=host)
    result=$(xe host-call-plugin host-uuid=$h plugin=trim fn=do_trim args:sr_uuid=$sr)
    echo "  reclaimed freed space on $sr: $result"
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    [ "${result,,}" = "true" ] || { echo "trim failed: $result" >&2; exit 1; }
    echo "OK: reclaim-space"
}
