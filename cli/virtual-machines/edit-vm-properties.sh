# Edit VM properties.
#
# Change a VM's description and custom metadata, then read the changes back.
#
# Run it:
#   ./workflows.sh edit-vm-properties https://xenserver root "$password"

edit_vm_properties() {
    vm=$(vm_uuid web-01)
    original=$(xe vm-param-get uuid=$vm param-name=name-description)
    xe vm-param-set uuid=$vm name-description="Edited by the xe example"
    xe vm-param-add uuid=$vm param-name=other-config xe_example=true
    echo "New description: $(xe vm-param-get uuid=$vm param-name=name-description)"
    echo "other-config[xe_example] = $(xe vm-param-get uuid=$vm param-name=other-config param-key=xe_example)"
    xe vm-param-set uuid=$vm name-description="$original"
    xe vm-param-remove uuid=$vm param-name=other-config param-key=xe_example
    echo "OK: edit-vm-properties"
}
