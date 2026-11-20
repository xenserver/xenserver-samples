# Manage VM groups.
#
# Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then take
# the VM out again and delete the group.
#
# Run it:
#   ./workflows.sh manage-vm-groups https://xenserver root "$password"

manage_vm_groups() {
    local vm_name=web-01
    vm=$(vm_uuid "$vm_name")
    # anti-affinity asks the pool to keep the group's members on different hosts.
    group=$(remote_xe vm-group-create name-label=xe-example-group placement=anti-affinity)
    echo "Created group:  $group"

    # Membership is written from the VM side, and read back from the group side.
    remote_xe vm-param-set uuid=$vm groups=$group
    members=$(set_to_csv "$(remote_xe vm-group-param-get uuid=$group param-name=vm-uuids)")
    echo "Group members:  $(count_csv "$members")"
    for m in $(each_csv "$members"); do
        echo "  $(remote_xe vm-param-get uuid=$m param-name=name-label)"
    done

    # vm-group-destroy already clears the group from every member VM on its own - no need to remove
    # membership ourselves first. Read both back afterwards to confirm.
    remote_xe vm-group-destroy uuid=$group
    if [ -z "$(set_to_csv "$(remote_xe vm-param-get uuid=$vm param-name=groups)")" ] \
        && [ -z "$(remote_xe vm-group-list uuid=$group --minimal)" ]; then
        echo "Removed $vm_name from the group; group deleted"
    else
        echo "group teardown incomplete" >&2
    fi
    ok manage-vm-groups
}
