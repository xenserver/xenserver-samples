# Checkpoint & revert.
#
# Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you would
# before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must have a guest OS
# with PV drivers (vm_name).
#
# Run it:
#   ./workflows.sh checkpoint-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (web-01)

# Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest freezes its
# processes and suspends itself. A guest that is still booting can fail to freeze a process that is busy
# starting up, and it then abandons the suspend without telling the host, which waits until
# VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here.
checkpoint_vm() {
    local vm_name=$(param vm_name "web-01")
    vm=$(vm_uuid "$vm_name")
    if [ "$(xe vm-param-get uuid=$vm param-name=power-state)" != "running" ]; then
        echo "$vm_name must be running to be checkpointed" >&2
        return 1
    fi
    # Running is not enough: the VM may have just been started (or restarted, as snapshot-revert does), so
    # wait for its guest to finish booting first.
    wait_for_guest_agent "$vm"
    cp=$(xe vm-checkpoint uuid=$vm new-name-label=xe-example-checkpoint-1)
    echo "Created checkpoint: $cp"
    xe snapshot-revert snapshot-uuid=$cp
    # A checkpoint's own power-state is always Suspended (it captures memory as well as disk), and
    # snapshot-revert restores exactly that - so the VM is Suspended here, not Running as it was before
    # the checkpoint, with a suspend-VDI holding the checkpoint's memory image. vm-resume picks up from
    # there (and frees that memory image).
    echo "Reverted $vm_name to the checkpoint; power-state now: $(xe vm-param-get uuid=$vm param-name=power-state)"
    xe vm-resume uuid=$vm
    echo "Resumed $vm_name; power-state now: $(xe vm-param-get uuid=$vm param-name=power-state)"
    # Tidy up so the example is repeatable. The checkpoint owns its own snapshot disks (and memory
    # image), separate from the VM's; snapshot-uninstall destroys them with the record.
    xe snapshot-uninstall snapshot-uuid=$cp force=true
    echo "Deleted the checkpoint."
    ok checkpoint-vm
}
