"""Change control domain memory.

Read and change a host's control domain (dom0) memory, then put it back. One setter pins the static
and dynamic bounds together, because dom0 does not balloon.

Run it::

    control_domain_memory("https://xenserver", "root", password)
"""

from connection import connect


def control_domain_memory(url, username, password):
    """Read and change a host's control domain (dom0) memory.

    VM.set_memory is a single-value setter: it pins the static and dynamic bounds and the
    target together, which is what dom0 needs — it does not balloon. The new size takes
    effect when the host next reboots, so in XenCenter this is offered only in maintenance
    mode; the API itself does not stop you."""
    session = connect(url, username, password)
    x = session.xenapi

    host = x.host.get_all()[0]
    dom0 = next(vm for vm in x.host.get_resident_VMs(host) if x.VM.get_is_control_domain(vm))
    original = int(x.VM.get_memory_dynamic_min(dom0))
    print("%s dom0: %.1f GiB" % (x.host.get_name_label(host), original / float(1024 ** 3)))

    x.VM.set_memory(dom0, str(original + 1024 ** 3))
    record = x.VM.get_record(dom0)
    print("  now %.1f GiB (static %s-%s, dynamic %s-%s)"
          % (int(record["memory_dynamic_min"]) / float(1024 ** 3),
             record["memory_static_min"], record["memory_static_max"],
             record["memory_dynamic_min"], record["memory_dynamic_max"]))

    x.VM.set_memory(dom0, str(original))     # leave the pool as we found it
    print("OK: control-domain-memory")
    session.logout()
