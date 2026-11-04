# Delete a VM.
#
# Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are destroyed
# explicitly afterward.
#
# Run it:
#   ./workflows.sh delete-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

delete_vm() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-example-delete sr-uuid=$(shared_sr))
    # vm-uninstall destroys the VM and the disks it owns, what XenCenter's Delete VM does; vm-destroy
    # would remove only the VM record and leave its disks behind.
    xe vm-uninstall uuid=$vm force=true
    echo "VM still present: $([ -z "$(xe vm-list uuid=$vm --minimal)" ] && echo false || echo true)"
    echo "OK: delete-vm"
}
