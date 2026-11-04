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
    xe vm-start uuid=$vm
    wait_for_guest_agent "$vm"
    vdi=$(first_disk_vdi "$vm")
    source=$(xe vdi-param-get uuid=$vdi param-name=sr-uuid)
    echo "Disk is on SR: $(xe sr-param-get uuid=$source param-name=name-label)"

    # Pick a different SR that holds disks (not ISO) and that the VM's host can reach (an attached PBD there).
    resident=$(xe vm-param-get uuid=$vm param-name=resident-on)
    dest=""
    for sr in $(each_csv "$(xe sr-list --minimal)"); do
        [ "$sr" = "$source" ] && continue
        [ "$(xe sr-param-get uuid=$sr param-name=content-type)" = "iso" ] && continue
        case "$(xe sr-param-get uuid=$sr param-name=type)" in iso|udev) continue ;; esac
        if [ -n "$(xe pbd-list sr-uuid=$sr host-uuid=$resident currently-attached=true --minimal)" ]; then
            dest=$sr; break
        fi
    done
    # vdi-pool-migrate moves the disk in place: the copy on the destination SR replaces the original.
    xe vdi-pool-migrate uuid=$vdi sr-uuid=$dest
    echo "Disk moved to: $(xe sr-param-get uuid=$(xe vdi-param-get uuid=$vdi param-name=sr-uuid) param-name=name-label)"

    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it now owns
    # (vm-destroy would leave the disks behind).
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    echo "OK: storage-migrate"
}
