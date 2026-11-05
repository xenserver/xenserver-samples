# Manage VM disks.
#
# Deactivate a running VM's disk, resize it, reactivate it — the Activate/Deactivate and Resize operations
# from the VM's Storage tab.
#
# Run it:
#   ./workflows.sh manage-vm-disks https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)
#   sr_name (Shared NFS)

# Not the VM's root/boot disk: a real VM's system disk is unpluggable=false (only a template's non-system
# disks default to unpluggable), so vbd-unplug on it fails on a real host with VBD_NOT_UNPLUGGABLE - and
# the VM has to be running in the first place, or unplug fails with VM_BAD_POWER_STATE. Work on a data
# disk this example adds to its own throwaway VM instead, and tidy up afterwards so the example is
# repeatable. No shrink: real SR backends refuse one outright (SR_BACKEND_FAILURE_79), so this only ever
# grows.
#
# Plugging and unplugging a disk on a running VM needs the guest's PV drivers (VM_MISSING_PV_DRIVERS
# otherwise), so the VM is a throwaway copy of source_vm, a VM with a guest OS and PV drivers.
manage_vm_disks() {
    local source_vm sr_name sr device sr_type sm
    source_vm=$(param source_vm "web-01")
    sr_name=$(param sr_name "Shared NFS")
    sr=$(first_csv "$(xe sr-list name-label="$sr_name" --minimal)")
    vm=$(copy_of_guest "$source_vm" "xe-example-vm-disks")
    xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"

    vdi=$(xe vdi-create sr-uuid=$sr name-label=xe-example-data-disk virtual-size=4GiB type=user)
    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=allowed-VBD-devices)")")
    vbd=$(xe vbd-create vm-uuid=$vm vdi-uuid=$vdi device=$device type=Disk mode=RW)
    xe vbd-plug uuid=$vbd
    echo "Disk attached:  $(xe vbd-param-get uuid=$vbd param-name=currently-attached)"

    # Deactivate: the disk stays with the VM, it is just no longer live.
    xe vbd-unplug uuid=$vbd
    echo "After unplug:   $(xe vbd-param-get uuid=$vbd param-name=currently-attached)"

    size=$(xe vdi-param-get uuid=$vdi param-name=virtual-size)
    xe vdi-resize uuid=$vdi disk-size=$((size * 2))
    echo "Resized:        $size -> $(xe vdi-param-get uuid=$vdi param-name=virtual-size) bytes"

    xe vbd-plug uuid=$vbd
    echo "After plug:     $(xe vbd-param-get uuid=$vbd param-name=currently-attached)"

    # Growing a disk that is attached and live is a DIFFERENT call, not a flag on the same one: online=true
    # tells the storage layer the guest is using the disk while it grows. Only some storage drivers can
    # (none of a stock XenServer 9's do), and the rest refuse with SR_OPERATION_NOT_SUPPORTED - so ask the
    # SR's driver (its SM record's features) first.
    sr_type=$(xe sr-param-get uuid=$sr param-name=type)
    sm=$(first_csv "$(xe sm-list type=$sr_type --minimal)")
    if [ -n "$sm" ] && xe sm-param-get uuid=$sm param-name=features param-key=VDI_RESIZE_ONLINE >/dev/null 2>&1; then
        grown=$(( $(xe vdi-param-get uuid=$vdi param-name=virtual-size) + 1073741824 ))
        xe vdi-resize uuid=$vdi disk-size=$grown online=true
        echo "Grown online:   $(xe vdi-param-get uuid=$vdi param-name=virtual-size) bytes"
    else
        echo "Grown online:   not supported by $sr_type storage; unplug, resize, plug as above"
    fi

    # Tidy up so the example is repeatable. vm-uninstall destroys the VM and only the disks it OWNS (VBD
    # other-config:owner, which vm-install sets) - not one attached later with a plain vbd-create, so
    # destroy the data disk too.
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    xe vdi-destroy uuid=$vdi
    echo "OK: manage-vm-disks"
}
