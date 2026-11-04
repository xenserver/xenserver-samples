# Checkpoint & revert.
#
# Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you would
# before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works on a throwaway
# copy of a VM with a guest OS and PV drivers (source_vm).
#
# Run it:
#   ./workflows.sh checkpoint-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)

# Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), hence a copy of
# source_vm - a VM with a guest OS and PV drivers - rather than an OS-less template clone.
checkpoint_vm() {
    local source_vm=$(param source_vm "web-01")
    vm=$(copy_of_guest "$source_vm" "xe-example-checkpoint")
    xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"
    cp=$(xe vm-checkpoint uuid=$vm new-name-label=xe-example-checkpoint-1)
    echo "Created checkpoint: $cp"
    xe snapshot-revert snapshot-uuid=$cp
    # A checkpoint's own power-state is always Suspended (it captures memory as well as disk), and
    # snapshot-revert restores exactly that - so the VM is Suspended here, not Running as it was before
    # the checkpoint, with a suspend-VDI holding the checkpoint's memory image. vm-resume clears that:
    # destroying a Suspended VM directly leaves that suspend-VDI behind as a storage leak.
    echo "Reverted to the checkpoint; power-state now: $(xe vm-param-get uuid=$vm param-name=power-state)"
    xe vm-resume uuid=$vm
    # Tidy up so the example is repeatable. The checkpoint owns its own snapshot disks (and memory
    # image), separate from the VM's; the -uninstall commands destroy them with the records.
    xe snapshot-uninstall snapshot-uuid=$cp force=true
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    echo "OK: checkpoint-vm"
}
