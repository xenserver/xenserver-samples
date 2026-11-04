# Snapshot & revert.
#
# Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a risky
# change.
#
# Run it:
#   ./workflows.sh snapshot-revert https://xenserver root "$password"

snapshot_revert() {
    vm=$(vm_uuid web-01)
    was_running=$([ "$(xe vm-param-get uuid=$vm param-name=power-state)" = "running" ] && echo true || echo false)
    snap=$(xe vm-snapshot uuid=$vm new-name-label=xe-example-snapshot)
    echo "Created snapshot: $snap"
    xe snapshot-revert snapshot-uuid=$snap
    echo "Reverted to the snapshot."
    # The other languages fetch the snapshot's console thumbnail from GET /vncsnapshot here. `xe` has no
    # command for a plain HTTP transfer that is not vm-export/host-backup, so there is nothing honest to
    # write - the thumbnail is a client-side fetch, not a CLI operation.
    # Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-down a running VM before
    # reverting it), even if it was Running a moment ago - restart it if that's how we found it, so the
    # example actually restores what it changed.
    [ "$was_running" = true ] && xe vm-start uuid=$vm
    # A snapshot owns its own snapshot disks; snapshot-uninstall removes them with it (the VM's disks are
    # untouched - they are not the snapshot's).
    xe snapshot-uninstall snapshot-uuid=$snap force=true
    echo "OK: snapshot-revert"
}
