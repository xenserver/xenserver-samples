# Inventory a VM's disks.
#
# List a VM's attached disks and the size of each.
#
# Run it:
#   ./workflows.sh vbd-inventory https://xenserver root "$password"

vbd_inventory() {
    vm=$(vm_uuid db-01)
    echo "Disks of db-01:"
    vbds=$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=VBDs)")
    for vbd in ${vbds//,/ }; do
        if [ "$(xe vbd-param-get uuid=$vbd param-name=type)" = "Disk" ]; then
            vdi=$(xe vbd-param-get uuid=$vbd param-name=vdi-uuid)
            echo "  - device $(xe vbd-param-get uuid=$vbd param-name=userdevice): $(xe vdi-param-get uuid=$vdi param-name=virtual-size) bytes"
        fi
    done
    echo "OK: vbd-inventory"
}
