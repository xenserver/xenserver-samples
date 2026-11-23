"""List networks.

Enumerate the pool's networks with their physical and virtual interface counts.

Run it::

    list_networks("https://xenserver", "root", password)
"""

from connection import connect


def list_networks(url, username, password):
    """List the pool's networks with their attached PIF and VIF counts."""
    session = connect(url, username, password)
    nets = sorted(session.xenapi.network.get_all_records().values(), key=lambda n: n["name_label"])
    print("Networks (%d):" % len(nets))
    for net in nets:
        print("  - %s: %d PIF(s), %d VIF(s)"
              % (net["name_label"], len(net["PIFs"]), len(net["VIFs"])))
    print("OK: list-networks")
    session.xenapi.session.logout()
