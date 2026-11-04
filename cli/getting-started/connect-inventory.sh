# Connect & inventory.
#
# Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual machines
# with their power state. This is the starting point for every session.
#
# Run it:
#   ./workflows.sh connect-inventory https://xenserver root "$password"

connect_inventory() {
    echo "Connected to pool: $(xe pool-list params=name-label --minimal)"
    echo "Hosts: $(xe host-list params=name-label --minimal)"
    echo "VMs:"
    xe vm-list is-control-domain=false params=name-label,power-state
    echo "OK: connect-inventory"
}
