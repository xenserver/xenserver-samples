# Clone a VM.
#
# Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy — the
# quick way to stamp out new VMs from a halted "golden" image.
#
# Run it:
#   ./workflows.sh clone-vm https://xenserver root "$password"

clone_vm() {
    local vm was_running
    vm=$(vm_uuid db-01)
    # vm-clone (like vm-copy) only works on a Halted VM - a running source fails with VM_BAD_POWER_STATE -
    # so shut it down first if it's running, and start it back up again after the clone.
    was_running=$([ "$(xe vm-param-get uuid=$vm param-name=power-state)" = "running" ] && echo true || echo false)
    [ "$was_running" = true ] && xe vm-shutdown uuid=$vm
    clone=$(xe vm-clone uuid=$vm new-name-label=xe-example-clone)
    echo "Cloned VM: $clone"
    [ "$was_running" = true ] && xe vm-start uuid=$vm
    # Tidy up: vm-uninstall destroys the clone and the disks it owns (vm-destroy would leave them).
    xe vm-uninstall uuid=$clone force=true
    echo "OK: clone-vm"
}
