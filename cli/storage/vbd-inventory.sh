# Inventory a VM's disks.
#
# List a VM's attached disks and the size of each.
#
# Run it:
#   ./workflows.sh vbd-inventory https://xenserver root "$password"

vbd_inventory() {
    vm=$(vm_uuid db-01)
    echo "Disks of db-01:"
    vbds=$(set_to_csv "$(remote_xe vm-param-get uuid=$vm param-name=VBDs)")
    for vbd in ${vbds//,/ }; do
        if [ "$(remote_xe vbd-param-get uuid=$vbd param-name=type)" = "Disk" ]; then
            vdi=$(remote_xe vbd-param-get uuid=$vbd param-name=vdi-uuid)
            size=$(remote_xe vdi-param-get uuid=$vdi param-name=virtual-size)
            echo "  - device $(remote_xe vbd-param-get uuid=$vbd param-name=userdevice): $((size / 1073741824)) GiB"
        fi
    done
    ok vbd-inventory
}
