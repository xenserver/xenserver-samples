# Rename an object.
#
# Change an object's name and read it back — how any object is renamed.
#
# Run it:
#   ./workflows.sh rename-object https://xenserver root "$password"

rename_object() {
    vm=$(vm_uuid web-01)
    original=$(xe vm-param-get uuid=$vm param-name=name-label)
    xe vm-param-set uuid=$vm name-label=xe-renamed
    echo "Renamed '$original' -> '$(xe vm-param-get uuid=$vm param-name=name-label)'"
    xe vm-param-set uuid=$vm name-label="$original"   # restore so the example is repeatable
    echo "OK: rename-object"
}
