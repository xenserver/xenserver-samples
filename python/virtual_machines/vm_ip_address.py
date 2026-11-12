"""Get a VM's IP address.

Read a named VM's IP address from its guest metrics, as reported by the in-guest agent.

Run it::

    vm_ip_address("https://xenserver", "root", password, "web-01")
"""

import time

from connection import connect
from helpers import is_set, vm_by_name


def vm_ip_address(url, username, password, vm_name="web-01", timeout=60, interval=2):
    """Read the named VM's IP from its guest metrics (VM_guest_metrics.networks).

    A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
    empty networks map) - retry for a while before concluding it has no guest agent reporting."""
    session = connect(url, username, password)
    vm_ref = vm_by_name(session, vm_name)
    deadline = time.time() + timeout
    ip = None
    while True:
        # An IP only shows up once the guest's tools report in, keyed "<vif device>/ip" (e.g. "0/ip").
        record = session.xenapi.VM.get_record(vm_ref)
        if record["power_state"] == "Running" and is_set(record["guest_metrics"]):
            ip = session.xenapi.VM_guest_metrics.get_record(record["guest_metrics"])["networks"].get("0/ip")
            if ip:
                break
        if time.time() > deadline:
            break
        time.sleep(interval)
    if ip:
        print("  %s: %s" % (vm_name, ip))
    else:
        print("  %s: no IP address reported yet (no guest agent running?)" % vm_name)
    print("OK: vm-ip-address")
    session.xenapi.session.logout()
