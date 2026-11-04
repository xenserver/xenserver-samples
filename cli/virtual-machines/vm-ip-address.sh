# Get a VM's IP address.
#
# Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
#
# Run it:
#   ./workflows.sh vm-ip-address https://xenserver root "$password"

vm_ip_address() {
    # A running guest's tools report its IPs in the VM's networks parameter, keyed "<vif device>/ip". Pick
    # one that reports an address (freshly-created VMs and guests without tools report none).
    running=$(xe vm-list power-state=running is-control-domain=false --minimal)
    vm=""; ip=""
    for u in $(each_csv "$running"); do
        ip=$(xe vm-param-get uuid=$u param-name=networks param-key=0/ip 2>/dev/null) || continue
        vm=$u; break
    done
    [ -n "$vm" ] || { vm=$(first_csv "$running"); ip="(no address reported)"; }
    echo "  $(xe vm-param-get uuid=$vm param-name=name-label): $ip"
    echo "OK: vm-ip-address"
}
