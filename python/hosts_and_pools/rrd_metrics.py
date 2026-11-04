"""Read RRD performance metrics.

Pull recent host performance samples from the RRD archives over the performance-data HTTP API, parse
the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space utilisation
per host).
"""

import json
import ssl
import time
import urllib.request

from connection import connect


def rrd_metrics(url, username, password):
    session = connect(url, username, password)
    # The RRD time-series isn't a XenAPI call; read the last 5 minutes over HTTP from rrd_updates.
    # Legends look like "AVERAGE:host:<uuid>:<datasource>"; values[] aligns to legend[].
    start = int(time.time()) - 300
    req = urllib.request.Request(
        "%s/rrd_updates?session_id=%s&host=true&start=%d" % (url, session._session, start),
        headers={"accept": "application/json"})
    data = json.load(urllib.request.urlopen(req, context=ssl._create_unverified_context()))
    legends = data["meta"]["legend"]

    peak = {}
    for point in data["data"]:
        for k, legend in enumerate(legends):
            parts = legend.split(":")
            if parts[1] == "host" and parts[3] == "pvsaccelerator_space_utilization":
                value = float(point["values"][k])
                if value != value:  # NaN: a gap in the series, not a real sample - never let it stick
                    continue
                if parts[2] not in peak or value > peak[parts[2]]:
                    peak[parts[2]] = value
    for host in session.xenapi.host.get_all_records().values():
        if host["uuid"] in peak:
            print("  %s: peak PVS cache utilisation %d%%" % (host["name_label"], peak[host["uuid"]]))
    print("OK: rrd-metrics")
    session.logout()
