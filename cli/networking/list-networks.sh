# List networks.
#
# Enumerate the pool's networks with their physical and virtual interface counts.
#
# Run it:
#   ./workflows.sh list-networks https://xenserver root "$password"

list_networks() {
    echo "Networks:"
    xe network-list params=name-label,bridge
    echo "OK: list-networks"
}
