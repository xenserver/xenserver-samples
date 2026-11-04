"""Connect & inventory.

Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual
machines with their power state. This is the starting point for every session.

Run it::

    connect_inventory("https://xenserver", "root", password)
"""

from connection import connect


def connect_inventory(url, username, password):
    """Log in and take an inventory of the pool: its name, its hosts and its VMs."""
    session = connect(url, username, password)
    pool = list(session.xenapi.pool.get_all_records().values())[0]
    print("Connected to pool: %s" % pool["name_label"])

    hosts = session.xenapi.host.get_all_records()
    print("Hosts (%d):" % len(hosts))
    for host in hosts.values():
        print("  - %s (%s)" % (host["name_label"], host["address"]))

    vms = [v for v in session.xenapi.VM.get_all_records().values()
           if not v["is_a_template"] and not v["is_control_domain"]]
    print("VMs (%d):" % len(vms))
    for vm in vms:
        print("  - %s [%s]" % (vm["name_label"], vm["power_state"]))

    print("OK: connect-inventory")
    session.xenapi.session.logout()
