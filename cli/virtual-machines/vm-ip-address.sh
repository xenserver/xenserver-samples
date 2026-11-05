# Get a VM's IP address.
#
# Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
#
# Run it:
#   ./workflows.sh vm-ip-address https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   timeout (60), interval (2)

vm_ip_address() {
    # A VM that has only just started may not have reported in yet (freshly-created VMs and guests
    # without tools report no address) - retry for a while rather than giving up on the first look.
    local timeout interval deadline running vm ip
    timeout=$(param timeout 60)
    interval=$(param interval 2)
    deadline=$((SECONDS + timeout))
    while true; do
        # A running guest's tools report its IPs in the VM's networks parameter, keyed "<vif device>/ip".
        running=$(xe vm-list power-state=running is-control-domain=false --minimal)
        vm=""; ip=""
        for u in $(each_csv "$running"); do
            ip=$(xe vm-param-get uuid=$u param-name=networks param-key=0/ip 2>/dev/null) || continue
            vm=$u; break
        done
        [ -n "$ip" ] && break
        [ $SECONDS -gt $deadline ] && break
        sleep "$interval"
    done
    if [ -z "$ip" ]; then
        echo "no running guest reported an IP address within ${timeout}s" >&2
        exit 1
    fi
    echo "  $(xe vm-param-get uuid=$vm param-name=name-label): $ip"
    echo "OK: vm-ip-address"
}
