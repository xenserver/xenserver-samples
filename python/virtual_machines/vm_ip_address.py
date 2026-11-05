"""Get a VM's IP address.

Read a running VM's IP address from its guest metrics, as reported by the in-guest agent.
"""

import time

from connection import connect


def vm_ip_address(url, username, password, timeout=60, interval=2):
    """Read a running VM's IP from its guest metrics (VM_guest_metrics.networks).

    A VM that has only just started may not have reported in yet (no guest_metrics at all, or an
    empty networks map) - retry for a while rather than giving up on the first look."""
    session = connect(url, username, password)
    deadline = time.time() + timeout
    while True:
        # A running guest reports its IP in networks, keyed "<vif device>/ip" (e.g. "0/ip"). Not every
        # running VM has one (no guest tools, no NIC, still booting), so look at each until one does.
        vm, ip = None, None
        for v in session.xenapi.VM.get_all_records().values():
            if (v["power_state"] == "Running" and not v["is_a_template"] and not v["is_control_domain"]
                    and v["guest_metrics"] != "OpaqueRef:NULL"):
                ip = session.xenapi.VM_guest_metrics.get_record(v["guest_metrics"])["networks"].get("0/ip")
                if ip:
                    vm = v
                    break
        if ip:
            print("  %s: %s" % (vm["name_label"], ip))
            break
        if time.time() > deadline:
            raise RuntimeError("no running guest reported an IP address within %ds" % timeout)
        time.sleep(interval)
    print("OK: vm-ip-address")
    session.logout()
