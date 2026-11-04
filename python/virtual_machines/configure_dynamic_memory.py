"""Configure dynamic memory.

Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the
ordering rule the four bounds must obey enforced.
"""

import XenAPI

from connection import connect


def configure_dynamic_memory(url, username, password):
    """Give a VM a dynamic memory range, so the host can reclaim memory from it under
    pressure instead of the VM holding a fixed amount.

    The four bounds must stay ordered: static_min <= dynamic_min <= dynamic_max <=
    static_max. The dynamic pair is what ballooning moves between; the static pair is the
    hard limit and can only be changed while the VM is off."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = next(ref for ref, v in x.VM.get_all_records().items()
              if not v["is_a_template"] and not v["is_control_domain"]
              and not v["is_a_snapshot"] and v["power_state"] == "Halted")
    before = x.VM.get_record(vm)
    print("%s: static %s-%s, dynamic %s-%s"
          % (before["name_label"], gib(before["memory_static_min"]), gib(before["memory_static_max"]),
             gib(before["memory_dynamic_min"]), gib(before["memory_dynamic_max"])))

    # Room to balloon: let the host squeeze the VM down to a quarter of its maximum, but never
    # below the static floor, which is the least the guest can boot in.
    floor = max(int(before["memory_static_min"]), int(before["memory_static_max"]) // 4)
    ceiling = int(before["memory_static_max"])
    x.VM.set_memory_dynamic_range(vm, str(floor), str(ceiling))
    after = x.VM.get_record(vm)
    print("  dynamic range now %s-%s" % (gib(after["memory_dynamic_min"]), gib(after["memory_dynamic_max"])))

    # The ordering is enforced, not advisory: a range wider than the static bounds is
    # refused rather than quietly clamped.
    try:
        x.VM.set_memory_dynamic_range(vm, str(floor), str(ceiling * 2))
        print("  ERROR: an out-of-range maximum was accepted")
    except XenAPI.Failure as e:
        print("  refused a dynamic_max above static_max: %s" % e.details[0])

    # str() throughout: memory is a 64-bit byte count and the binding's transport cannot carry
    # an integer that large, so the API takes these as strings.
    x.VM.set_memory_dynamic_range(vm, str(before["memory_dynamic_min"]), str(before["memory_dynamic_max"]))
    print("OK: configure-dynamic-memory")
    session.logout()


def gib(value):
    return "%.1f GiB" % (int(value) / float(1024 ** 3))
