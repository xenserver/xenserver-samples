# Connect & inventory.
#
# Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual machines
# with their power state. This is the starting point for every session.
#
# Run it:
#   ./workflows.sh connect-inventory https://xenserver root "$password"

connect_inventory() {
    # A pool often has no name of its own; show its coordinator's name instead.
    pool_name=$(xe pool-list params=name-label --minimal)
    if [ -z "$pool_name" ]; then
        master=$(xe pool-list params=master --minimal)
        pool_name=$(xe host-list uuid=$master params=name-label --minimal)
    fi
    echo "Connected to pool: $pool_name"
    echo "Hosts: $(xe host-list params=name-label --minimal)"
    echo "VMs:"
    xe vm-list is-control-domain=false params=name-label,power-state
    ok connect-inventory
}
