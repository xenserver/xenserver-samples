"""Collect a server status report.

Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the
whole bundle, then download a smaller one covering only the sections you pick.
"""

import os
import shutil
import ssl
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

from connection import connect


def server_status_report(url, username, password):
    """Gather a host's diagnostic bundle -- the archive support asks for.

    The host publishes a catalogue of the sections it can report on, each with a size
    estimate and whether it may contain personal data, so a client can offer an informed
    choice rather than hard-coding the list. The bundle itself is an HTTP download
    alongside the API, and the chosen sections travel in the query string."""
    session = connect(url, username, password)
    x = session.xenapi
    ctx = ssl._create_unverified_context()

    # Report on the coordinator. Each host answers for itself, so which one you ask decides
    # whose logs you get -- support normally wants every host, one download each.
    host = x.pool.get_master(x.pool.get_all()[0])
    print("Status report for %s" % x.host.get_name_label(host))

    keys, defaults = [], []
    for capability in ET.fromstring(x.host.get_system_status_capabilities(host)):
        keys.append(capability.get("key"))
        if capability.get("default-checked") == "yes":
            defaults.append(capability.get("key"))
        print("  %-22s max %9s bytes  default=%-3s pii=%s"
              % (capability.get("key"), capability.get("max-size"),
                 capability.get("default-checked"), capability.get("pii")))

    # Take the sections the host marks default-checked: asking for every section can mean gigabytes (VM
    # memory dumps, every log) and a long wait while the host builds it.
    whole = fetch_status_report(url, session, ctx, defaults)
    print("default sections (%d of %d): %d bytes" % (len(defaults), len(keys), whole))

    # Pick a real, small section from the host's own catalogue rather than assuming a name: the
    # catalogue is server-defined (xen-bugtool's own --capabilities output), not a fixed client
    # list, and "xenserver-config" isn't one of the real keys any host actually publishes.
    subset_key = next((k for k in keys if k in ("firstboot", "network-status")), keys[0])
    subset = fetch_status_report(url, session, ctx, [subset_key])
    print("%s only:   %d bytes" % (subset_key, subset))
    if subset >= whole:
        print("  ERROR: selecting fewer sections did not produce a smaller bundle")

    print("OK: server-status-report")
    session.logout()


def fetch_status_report(url, session, ctx, entries):
    """Download the bundle for the given capability keys (a tar archive) to a file, streaming it -
    a report can be large - and return its size. This example then deletes it; you'd keep it."""
    request = "%s/system-status?session_id=%s&output=tar&entries=%s" \
              % (url, session._session, ",".join(entries))
    handle, path = tempfile.mkstemp(prefix="sdk-example-status-", suffix=".tar")
    try:
        with os.fdopen(handle, "wb") as out, urllib.request.urlopen(request, context=ctx) as response:
            shutil.copyfileobj(response, out, 1024 * 1024)
        return os.path.getsize(path)
    finally:
        os.remove(path)
