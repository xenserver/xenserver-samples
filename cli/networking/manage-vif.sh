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
    vm=$(xe vm-install template="$template" new-name-label=xe-example-vif)
    net=$(first_csv "$(xe network-list --minimal)")
    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=allowed-VIF-devices)")")
    vif=$(xe vif-create vm-uuid=$vm network-uuid=$net device=$device)
    # VMs have no "VIFs" field in xe (only the SDKs expose VM.VIFs directly) - count the VIF objects instead.
    vifs=$(xe vif-list vm-uuid=$vm --minimal)
    echo "Attached a VIF; VM now has $(count_csv "$vifs") NIC(s)"
    xe vif-destroy uuid=$vif
    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it owns (vm-destroy
    # would leave the disks behind).
    xe vm-uninstall uuid=$vm force=true
    ok manage-vif
}
