"""Create a NIC bond.

Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond
back, then dissolve it.

Run it::

    create_bond("https://xenserver", "root", password)
"""

from connection import connect


def create_bond(url, username, password):
    """Bond two spare NICs onto a new network, then dissolve the bond."""
    session = connect(url, username, password)
    x = session.xenapi
    host = x.host.get_all()[0]

    # Pick up any NIC racked since the host booted. Cheap, and without it a card added a moment ago is
    # not there to bond.
    x.PIF.scan(host)

    # Spare NICs only. A bond that includes the management interface moves the management address onto
    # the bond master — on a real host that is how you lose the connection you are working over.
    spares = [ref for ref, pif in x.PIF.get_all_records().items()
              if pif["host"] == host and not pif["management"] and pif["physical"]][:2]
    if len(spares) < 2:
        raise RuntimeError("%s has %d spare NIC(s); a bond needs two that aren't the management interface"
                           % (x.host.get_name_label(host), len(spares)))
    print("Bonding:      " + ", ".join(x.PIF.get_device(p) for p in spares))

    # The bond needs a network to sit on.
    network = x.network.create({
        "name_label": "sdk-example-bond",
        "name_description": "Created by the SDK example",
        "other_config": {},
    })

    bond = x.Bond.create(network, spares, "", "balance-slb")
    print(f"Bond master:  {x.PIF.get_device(x.Bond.get_master(bond))}")
    print(f"Mode:         {x.Bond.get_mode(bond)}")

    # Dissolving returns the NICs to standalone use (and moves management back, had it been bonded).
    x.Bond.destroy(bond)
    x.network.destroy(network)
    print(f"Bonds left:   {len(x.Bond.get_all())}")
    print("OK: create-bond")
    x.session.logout()
