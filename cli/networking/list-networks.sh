# List networks.
#
# Enumerate the pool's networks with their physical and virtual interface counts.
#
# Run it:
#   ./workflows.sh list-networks https://xenserver root "$password"

list_networks() {
    nets=$(xe network-list --minimal)
    echo "Networks ($(count_csv "$nets")):"
    for n in $(each_csv "$nets"); do
        printf '%s\t  - %s: %s PIF(s), %s VIF(s)\n' \
            "$(xe network-param-get uuid=$n param-name=name-label)" \
            "$(xe network-param-get uuid=$n param-name=name-label)" \
            "$(count_csv "$(set_to_csv "$(xe network-param-get uuid=$n param-name=PIF-uuids)")")" \
            "$(count_csv "$(set_to_csv "$(xe network-param-get uuid=$n param-name=VIF-uuids)")")"
    done | sort | cut -f2-
    ok list-networks
}
