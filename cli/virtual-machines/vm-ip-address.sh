# Get a VM's IP address.
#
# Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.
#
# Run it:
#   ./workflows.sh vm-ip-address https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (web-01), timeout (60), interval (2)

vm_ip_address() {
    # A VM that has only just started may not have reported in yet (freshly-created VMs and guests
    # without tools report no address) - retry for a while before concluding it has no guest agent
    # reporting.
    local vm_name timeout interval deadline vm power ip
    vm_name=$(param vm_name web-01)
    timeout=$(param timeout 60)
    interval=$(param interval 2)
    vm=$(vm_uuid "$vm_name")
    deadline=$((SECONDS + timeout))
    while true; do
        # An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
        power=$(xe vm-param-get uuid=$vm param-name=power-state)
        ip=""
        if [ "$power" = running ]; then
            ip=$(xe_try vm-param-get uuid=$vm param-name=networks param-key=0/ip 2>/dev/null) || ip=""
        fi
        [ -n "$ip" ] && break
        [ $SECONDS -gt $deadline ] && break
        sleep "$interval"
    done
    if [ -n "$ip" ]; then
        echo "  $vm_name: $ip"
    else
        echo "  $vm_name: no IP address reported yet (no guest agent running?)"
    fi
    ok vm-ip-address
}
