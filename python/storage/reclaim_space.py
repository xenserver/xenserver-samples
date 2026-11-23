"""Reclaim freed space on a thin SR.

Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable
SR, pick a host with a live connection to it, and run the trim operation.
"""

from connection import connect


def reclaim_space(url, username, password):
    """Reclaim space freed by deleted disks on a thin-provisioned SR ("Reclaim freed space").

    A thin SR supports the trim/do_trim host plugin. Find one via its storage manager's
    SR_TRIM feature, pick a host with a live (currently-attached) connection to it, and run
    the plugin.
    """
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    # Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
    trim_types = set(sm["type"] for sm in session.xenapi.SM.get_all_records().values()
                     if "SR_TRIM" in sm["features"])
    sr_ref, sr = next((ref, r) for ref, r in session.xenapi.SR.get_all_records().items()
                      if r["type"] in trim_types and int(r["physical_size"]) > 0)
    # A host with a currently-attached PBD can reach the SR to run the plugin.
    host = next(pbd["host"] for pbd in
                (session.xenapi.PBD.get_record(ref) for ref in sr["PBDs"])
                if pbd["currently_attached"])

    print("  %s: %d / %d GiB used"
          % (sr["name_label"], int(sr["physical_utilisation"]) // GIB, int(sr["physical_size"]) // GIB))

    result = session.xenapi.host.call_plugin(host, "trim", "do_trim", {"sr_uuid": sr["uuid"]})
    print("  reclaimed freed space on %s: %s" % (sr["name_label"], result))
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    assert result.strip().lower() == "true", "trim plugin returned %r" % result

    # Rescan to refresh utilisation from the backend, the same way sr_usage does, before reporting it.
    session.xenapi.SR.scan(sr_ref)
    used_after = int(session.xenapi.SR.get_physical_utilisation(sr_ref))
    print("  %s: %d / %d GiB used" % (sr["name_label"], used_after // GIB, int(sr["physical_size"]) // GIB))
    print("OK: reclaim-space")
    session.logout()
