"""Create a network.

Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to
each other privately.

Run it::

    create_network("https://xenserver", "root", password, "sdk-example-net")
"""

from connection import connect


def create_network(url, username, password, network_name="sdk-example-net"):
    """Create an internal network (an isolated switch with no physical NIC)."""
    session = connect(url, username, password)
    net_ref = session.xenapi.network.create({
        "name_label": network_name,
        "name_description": "Internal network created by the SDK example",
        "MTU": "1500",
        "other_config": {},
    })
    print("Created network: %s" % session.xenapi.network.get_uuid(net_ref))

    # Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this is
    # a property of the network rather than of any one interface on it.
    session.xenapi.network.set_MTU(net_ref, "9000")
    print("MTU now:         %s" % session.xenapi.network.get_MTU(net_ref))

    session.xenapi.network.destroy(net_ref)
    print("OK: create-network")
    session.xenapi.session.logout()
