# Manage VM groups.
#
# Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then take
# the VM out again and delete the group.
#
# Run it:
#   ./workflows.sh manage-vm-groups https://xenserver root "$password"

manage_vm_groups() {
    vm=$(vm_uuid web-01)
    # anti-affinity asks the pool to keep the group's members on different hosts.
    group=$(xe vm-group-create name-label=xe-example-group placement=anti-affinity)
    echo "Created group:  $group"

    # Membership is written from the VM side, and read back from the group side.
    xe vm-param-set uuid=$vm groups=$group
    echo "Group members:  $(count_csv "$(set_to_csv "$(xe vm-group-param-get uuid=$group param-name=vm-uuids)")")"

    # vm-group-destroy already clears the group from every member VM on its own - no need to remove
    # membership ourselves first.
    xe vm-group-destroy uuid=$group
    echo "OK: manage-vm-groups"
}
