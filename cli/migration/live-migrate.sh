# Live migrate a VM.
#
# Move a running VM to another host in the pool with no downtime: check the destination can boot it,
# live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and PV drivers
# (source_vm), with its disks moved first to a shared storage repository (sr_name) so the destination host can
# see them.
#
# Run it:
#   ./workflows.sh live-migrate https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)
#   sr_name (Shared NFS)

# Live migration needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so this moves a
# throwaway copy of source_vm, a VM with a guest OS and PV drivers. Only the VM's memory moves, so the
# destination host has to see its disks already: a disk on local storage refuses with VM_REQUIRES_SR.
# Put the copy's disks on the shared SR sr_name first.
live_migrate() {
    local source_vm sr_name
    source_vm=$(param source_vm "web-01")
    sr_name=$(param sr_name "Shared NFS")
    vm=$(copy_of_guest "$source_vm" "xe-example-migrate")
    move_disks_to_sr "$vm" "$(first_csv "$(xe sr-list name-label="$sr_name" shared=true --minimal)")"
    xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"
    source=$(xe vm-param-get uuid=$vm param-name=resident-on)
    echo "Running on: $(xe host-param-get uuid=$source param-name=name-label)"
    hosts=$(xe host-list --minimal); dest=""
    for h in ${hosts//,/ }; do [ "$h" != "$source" ] && { dest=$h; break; }; done
    xe vm-migrate uuid=$vm host-uuid=$dest live=true
    now=$(xe vm-param-get uuid=$vm param-name=resident-on)
    echo "Migrated to: $(xe host-param-get uuid=$now param-name=name-label)"
    # Tidy up so the example is repeatable: stop the VM, then vm-uninstall destroys it and the disks it
    # owns (vm-destroy would leave the disks behind).
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    echo "OK: live-migrate"
}
