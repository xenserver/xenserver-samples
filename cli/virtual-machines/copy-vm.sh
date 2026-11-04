# Copy a VM.
#
# Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks) — distinct
# from a fast, copy-on-write clone.
#
# Run it:
#   ./workflows.sh copy-vm https://xenserver root "$password"

copy_vm() {
    local vm was_running
    vm=$(vm_uuid db-01)
    # vm-copy (like vm-clone) only works on a Halted VM - a running source fails with VM_BAD_POWER_STATE -
    # so shut it down first if it's running, and start it back up again after the copy.
    was_running=$([ "$(xe vm-param-get uuid=$vm param-name=power-state)" = "running" ] && echo true || echo false)
    [ "$was_running" = true ] && xe vm-shutdown uuid=$vm
    copy=$(xe vm-copy uuid=$vm new-name-label=xe-example-copy sr-uuid=$(shared_sr))
    echo "Copied VM: $copy"
    [ "$was_running" = true ] && xe vm-start uuid=$vm
    # Tidy up: vm-uninstall destroys the copy and its disks, leaving the source VM intact.
    xe vm-uninstall uuid=$copy force=true
    echo "OK: copy-vm"
}
