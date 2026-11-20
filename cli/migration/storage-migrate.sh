# Storage live-migration.
#
# Move a running VM's virtual disk to a different storage repository while the VM keeps running — live storage
# migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
#
# Run it:
#   ./workflows.sh storage-migrate https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   source_vm (web-01)

# Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so this
# works on a throwaway copy of source_vm, a VM with a guest OS and PV drivers. (A halted VM's disk moves
# too, without the guest; what vdi-pool-migrate always needs is a VM to move the disk for - a VDI no VBD
# points at fails VDI_NEEDS_VM_FOR_MIGRATE.)
storage_migrate() {
    local source_vm=$(param source_vm "web-01")
    vm=$(copy_of_guest "$source_vm" "xe-example-storagemigrate")
    remote_xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"
    vdi=$(first_disk_vdi "$vm")
    source=$(remote_xe vdi-param-get uuid=$vdi param-name=sr-uuid)
    echo "Disk is on SR: $(remote_xe sr-param-get uuid=$source param-name=name-label)"

    # Pick a different SR that holds disks (not ISO), that the VM's host can reach (an attached PBD
    # there), and that has room for the disk - a host's local SR is often too small for a VM's disk.
    # Scan a candidate before trusting its free space: the size and utilisation xapi reports are only as
    # fresh as the SR's last scan, and can claim room the storage doesn't have. Live storage migration copies
    # a snapshot of the disk and mirrors the running disk on top of it, so the destination needs room for the
    # disk twice over (a thick-provisioned LVM SR allocates both).
    resident=$(remote_xe vm-param-get uuid=$vm param-name=resident-on)
    size=$(remote_xe vdi-param-get uuid=$vdi param-name=virtual-size)
    dest=""
    for sr in $(each_csv "$(remote_xe sr-list --minimal)"); do
        [ "$sr" = "$source" ] && continue
        [ "$(remote_xe sr-param-get uuid=$sr param-name=content-type)" = "iso" ] && continue
        case "$(remote_xe sr-param-get uuid=$sr param-name=type)" in iso|udev) continue ;; esac
        [ -n "$(remote_xe pbd-list sr-uuid=$sr host-uuid=$resident currently-attached=true --minimal)" ] || continue
        remote_xe sr-scan uuid=$sr
        free=$(( $(remote_xe sr-param-get uuid=$sr param-name=physical-size) - \
                 $(remote_xe sr-param-get uuid=$sr param-name=physical-utilisation) ))
        if [ "$free" -ge $((2 * size)) ]; then
            dest=$sr; break
        fi
    done
    if [ -z "$dest" ]; then
        # No destination SR fits: don't leave the throwaway VM behind.
        remote_xe vm-shutdown uuid=$vm force=true
        remote_xe vm-uninstall uuid=$vm force=true
        echo "no other SR attached to $(remote_xe host-param-get uuid=$resident param-name=name-label) has" \
             "room for the $((size / 1073741824)) GiB disk twice over" >&2
        exit 1
    fi
    # vdi-pool-migrate moves the disk in place, but under a NEW uuid - the old one stops existing, so read
    # back the one it prints rather than the one passed in.
    new_vdi=$(remote_xe vdi-pool-migrate uuid=$vdi sr-uuid=$dest)
    new_sr=$(remote_xe vdi-param-get uuid=$new_vdi param-name=sr-uuid)
    echo "Disk moved to: $(remote_xe sr-param-get uuid=$new_sr param-name=name-label)"

    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it now owns
    # (vm-destroy would leave the disks behind).
    remote_xe vm-shutdown uuid=$vm force=true
    remote_xe vm-uninstall uuid=$vm force=true
    echo "Cleaned up the example VM."
    ok storage-migrate
}
