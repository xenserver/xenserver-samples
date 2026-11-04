# Custom fields.
#
# Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the object.
#
# Run it:
#   ./workflows.sh custom-fields https://xenserver root "$password"

custom_fields() {
    vm=$(vm_uuid web-01)
    xe vm-param-set uuid=$vm other-config:XenCenter.CustomFields.Owner="Platform Team"
    echo "Owner = $(xe vm-param-get uuid=$vm param-name=other-config param-key=XenCenter.CustomFields.Owner)"
    xe vm-param-remove uuid=$vm param-name=other-config param-key=XenCenter.CustomFields.Owner
    echo "OK: custom-fields"
}
