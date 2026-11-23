# Create a network.
#
# Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to each other
# privately.
#
# Run it:
#   ./workflows.sh create-network https://xenserver root "$password"

create_network() {
    net=$(remote_xe network-create name-label=xe-example-net)
    echo "Created network: $net"

    # Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this
    # is a property of the network rather than of any one interface on it.
    remote_xe network-param-set uuid=$net MTU=9000
    echo "MTU now:         $(remote_xe network-param-get uuid=$net param-name=MTU)"
    remote_xe network-destroy uuid=$net
    ok create-network
}
