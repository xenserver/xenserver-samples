# Manage network interfaces.
#
# Attach a virtual network interface to a VM and remove it again.
#
# Run it:
#   ./workflows.sh manage-vif https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

manage_vif() {
    local template=$(param template_name "Rocky Linux 8") device
    vm=$(remote_xe vm-install template="$template" new-name-label=xe-example-vif)
    net=$(first_csv "$(remote_xe network-list --minimal)")
    device=$(first_csv "$(set_to_csv "$(remote_xe vm-param-get uuid=$vm param-name=allowed-VIF-devices)")")
    vif=$(remote_xe vif-create vm-uuid=$vm network-uuid=$net device=$device)
    # VMs have no "VIFs" field in xe (only the SDKs expose VM.VIFs directly) - count the VIF objects instead.
    vifs=$(remote_xe vif-list vm-uuid=$vm --minimal)
    echo "Attached a VIF; VM now has $(count_csv "$vifs") NIC(s)"

    remote_xe vif-destroy uuid=$vif
    echo "Removed the VIF; VM now has $(count_csv "$(remote_xe vif-list vm-uuid=$vm --minimal)") NIC(s)"

    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it owns (vm-destroy
    # would leave the disks behind).
    remote_xe vm-uninstall uuid=$vm force=true
    ok manage-vif
}
