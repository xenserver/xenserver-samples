# Look up an object by UUID.
#
# Resolve a stable UUID back to a live object reference — how to persist a reference to an object across
# sessions.
#
# Run it:
#   ./workflows.sh find-by-uuid https://xenserver root "$password"

find_by_uuid() {
    vm=$(vm_uuid web-01)
    echo "UUID $vm resolves to $(xe vm-param-get uuid=$vm param-name=name-label)"
    echo "OK: find-by-uuid"
}
