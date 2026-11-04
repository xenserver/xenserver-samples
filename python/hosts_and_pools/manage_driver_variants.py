"""Manage device driver variants.

Inspect a host's device drivers and choose which variant of one to use, seeing the difference
between the variant that is selected and the one currently loaded.
"""

from connection import connect


def manage_driver_variants(url, username, password):
    """Inspect a host's device drivers and choose which variant of one to use.

    A driver can ship in several variants -- a vendor build alongside the one in the
    distribution, say. One is *selected* (what the host will load) and one is *active* (what it
    has loaded); they differ until the host reboots, which is what makes selecting a variant a
    scheduled change rather than an immediate one."""
    session = connect(url, username, password)
    x = session.xenapi
    host = x.pool.get_master(x.pool.get_all()[0])

    drivers = {ref: r for ref, r in x.Host_driver.get_all_records().items() if r["host"] == host}
    print("%s has %d driver(s)" % (x.host.get_name_label(host), len(drivers)))
    for ref, driver in sorted(drivers.items(), key=lambda kv: kv[1]["name"])[:3]:
        print("  %-14s %-10s %d variant(s), active=%s"
              % (driver["name"], driver["type"], len(driver["variants"]),
                 variant_name(x, driver["active_variant"])))

    # Select a variant explicitly. It becomes the selected one immediately; whether it is also
    # active depends on whether the hardware is present and the driver already loaded.
    # Host_driver.select refuses a variant whose hardware isn't present (HOST_DRIVER_NO_HARDWARE) -
    # and a host lists drivers for plenty of devices it doesn't have - so pick a driver for hardware
    # this host actually has, and one of its variants that is usable.
    usable = [(ref, v) for ref, d in sorted(drivers.items(), key=lambda kv: kv[1]["name"])
              for v in d["variants"] if x.Driver_variant.get_hardware_present(v)]
    if not usable:
        raise RuntimeError("no driver on %s has a variant for hardware it has" % x.host.get_name_label(host))
    ref, variant = usable[0]
    x.Host_driver.select(ref, variant)
    after = x.Host_driver.get_record(ref)
    print("  %s: selected %s, active %s"
          % (after["name"], variant_name(x, after["selected_variant"]),
             variant_name(x, after["active_variant"])))

    print("OK: manage-driver-variants")
    session.logout()


def variant_name(x, ref):
    """A driver variant's name, tolerating the null reference an unloaded driver has."""
    return x.Driver_variant.get_name(ref) if ref and ref != "OpaqueRef:NULL" else "(none)"
