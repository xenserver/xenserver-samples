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
    session = connect(url, username, password)
    # Storage-manager backends that advertise SR_TRIM in their features map are trim-capable.
    trim_types = set(sm["type"] for sm in session.xenapi.SM.get_all_records().values()
                     if "SR_TRIM" in sm["features"])
    sr = next(r for r in session.xenapi.SR.get_all_records().values()
              if r["type"] in trim_types and int(r["physical_size"]) > 0)
    # A host with a currently-attached PBD can reach the SR to run the plugin.
    host = next(pbd["host"] for pbd in
                (session.xenapi.PBD.get_record(ref) for ref in sr["PBDs"])
                if pbd["currently_attached"])
    result = session.xenapi.host.call_plugin(host, "trim", "do_trim", {"sr_uuid": sr["uuid"]})
    print("  reclaimed freed space on %s: %s" % (sr["name_label"], result))
    # Compare case-insensitively: a real host's trim plugin answers "True" (capitalised).
    assert result.strip().lower() == "true", "trim plugin returned %r" % result
    print("OK: reclaim-space")
    session.logout()
