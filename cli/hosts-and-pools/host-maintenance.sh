# Enter & exit maintenance mode.
#
# Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running guests to
# another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and PV drivers
# (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation something to move.
#
# Run it:
#   ./workflows.sh host-maintenance https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)
#   sr_name (Shared NFS)

# Pins a throwaway copy of source_vm to a host (not the coordinator, so the coordinator can receive its
# evacuated guests) so evacuation has work to do. Evacuation live-migrates the guest, which needs its
# cooperation (VM_LACKS_FEATURE without PV drivers), so source_vm must have a guest OS with PV drivers.
#
# Evacuation also needs somewhere else in the pool that can actually see the VM's disk - a VM whose only
# disk is on local (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a pool's
# installation-time default SR is commonly local storage. Move the pinned VM's disk onto a shared SR
# (sr_name, below) explicitly rather than trusting whatever the pool default happens to be.
host_maintenance() {
    local source_vm sr_name
    source_vm=$(param source_vm "web-01")
    sr_name=$(param sr_name "Shared NFS")

    # Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
    master=$(xe pool-param-get uuid=$(first_csv "$(xe pool-list --minimal)") param-name=master)
    h=""
    for candidate in $(each_csv "$(xe host-list --minimal)"); do
        [ "$candidate" != "$master" ] && { h=$candidate; break; }
    done
    echo "Maintenance host: $(xe host-param-get uuid=$h param-name=name-label)"

    # Pin a copy of source_vm to that host so evacuation has something to move.
    vm=$(copy_of_guest "$source_vm" "xe-example-maint")
    move_disks_to_sr "$vm" "$(first_csv "$(xe sr-list name-label="$sr_name" shared=true --minimal)")"
    xe vm-param-set uuid=$vm affinity=$h
    xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"
    echo "Guest resident on:$(xe host-param-get uuid=$(xe vm-param-get uuid=$vm param-name=resident-on) param-name=name-label)"

    # Enter maintenance mode: disable the host, then evacuate its guests.
    xe host-disable uuid=$h;  echo "After disable:  enabled=$(xe host-param-get uuid=$h param-name=enabled)"
    xe host-evacuate uuid=$h; echo "After evacuate: guest now on $(xe host-param-get uuid=$(xe vm-param-get uuid=$vm param-name=resident-on) param-name=name-label)"
    xe host-enable uuid=$h;   echo "After enable:   enabled=$(xe host-param-get uuid=$h param-name=enabled)"
    # Tidy up so the example is repeatable: stop the VM, then vm-uninstall destroys it and the disks it
    # owns (vm-destroy would leave the disks behind).
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    echo "OK: host-maintenance"
}
