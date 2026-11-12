# VM power lifecycle.
#
# Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down cleanly.
# Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy of a VM with a
# guest OS and PV drivers (source_vm), which is deleted again with its disks afterwards.
#
# Run it:
#   ./workflows.sh vm-lifecycle https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)

vm_lifecycle() {
    local source_vm=$(param source_vm "web-01")
    # Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so
    # the copy is made from source_vm, a VM with a guest OS and PV drivers, and the example waits for the
    # guest to report in after starting.
    vm=$(copy_of_guest "$source_vm" "xe-example-lifecycle")
    echo "Initial: $(xe vm-param-get uuid=$vm param-name=power-state)"
    xe vm-start uuid=$vm;   echo "After start:    $(xe vm-param-get uuid=$vm param-name=power-state)"
    wait_for_guest_agent "$vm"
    # The emulated hardware can be restarted under a running guest without rebooting it.
    xe vm-restart-device-models uuid=$vm
    echo "Device models restarted; still $(xe vm-param-get uuid=$vm param-name=power-state)"
    if has_suspend_sr "$vm"; then
        xe vm-suspend uuid=$vm; echo "After suspend:  $(xe vm-param-get uuid=$vm param-name=power-state)"
        xe vm-resume uuid=$vm;  echo "After resume:   $(xe vm-param-get uuid=$vm param-name=power-state)"
        wait_for_guest_agent "$vm"   # the PV drivers reconnect after a resume
    else
        echo "Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host"
    fi
    # A clean shutdown asks the guest OS to shut itself down, as pressing the power button would - safe
    # now that the VM is a copy of a guest with PV drivers (an OS-less template clone would hang or fail
    # for real on a real host, with no public fallback to a hard shutdown).
    xe vm-shutdown uuid=$vm; echo "After shutdown: $(xe vm-param-get uuid=$vm param-name=power-state)"
    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it owns (vm-destroy
    # would leave the disks behind).
    xe vm-uninstall uuid=$vm force=true
    ok vm-lifecycle
}

# Whether VM.suspend has a suspend-image SR to use: the VM's own, else the pool's, else the resident
# host's - the same fallback order xapi's choose_suspend_sr uses. Each xe call is assigned before it is
# tested, not tested directly in "$(...)" - a transient failure (xe is fatal; this would otherwise never
# run) must not be read as "no SR configured".
has_suspend_sr() {
    # Not "host": that name is the connection target xe() dials (connection.sh), and shadowing it here
    # would send every xe call below to an empty address instead.
    local vm=$1 pool master sr
    sr=$(xe vm-param-get uuid=$vm param-name=suspend-SR-uuid)
    [ -n "$sr" ] && return 0
    pool=$(first_csv "$(xe pool-list --minimal)")
    sr=$(xe pool-param-get uuid=$pool param-name=suspend-image-SR)
    [ -n "$sr" ] && return 0
    master=$(xe pool-param-get uuid=$pool param-name=master)
    sr=$(xe host-param-get uuid=$master param-name=suspend-image-sr-uuid)
    [ -n "$sr" ]
}
