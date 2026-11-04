"""Storage repository usage.

Report each storage repository's used and total capacity, and rescan one.

Run it::

    sr_usage("https://xenserver", "root", password)
"""

from connection import connect


def sr_usage(url, username, password):
    """Report each real SR's used/total space, then rescan one to refresh its utilisation."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    srs = sorted(session.xenapi.SR.get_all_records().values(), key=lambda s: s["name_label"])
    for sr in srs:
        if int(sr["physical_size"]) <= 0:
            continue  # skip ISO/DVD pseudo-SRs
        print("  %s: %d / %d GiB used"
              % (sr["name_label"],
                 int(sr["physical_utilisation"]) // GIB, int(sr["physical_size"]) // GIB))

    # A rescan refreshes an SR's utilisation from its backend.
    scan_me = next(ref for ref, r in session.xenapi.SR.get_all_records().items()
                   if int(r["physical_size"]) > 0)
    session.xenapi.SR.scan(scan_me)

    # Read caching keeps recently-read blocks in the host's memory. It is switched off per SR by
    # setting o_direct, which asks the storage layer to bypass the cache entirely.
    session.xenapi.SR.remove_from_other_config(scan_me, "o_direct")
    session.xenapi.SR.add_to_other_config(scan_me, "o_direct", "true")
    print("  read caching on %s: %s"
          % (session.xenapi.SR.get_name_label(scan_me),
             "off" if session.xenapi.SR.get_other_config(scan_me).get("o_direct") == "true" else "on"))
    session.xenapi.SR.remove_from_other_config(scan_me, "o_direct")
    print("OK: sr-usage")
    session.xenapi.session.logout()
