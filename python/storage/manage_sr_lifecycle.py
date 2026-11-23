"""Detach, reattach and forget storage.

Take a storage repository offline and bring it back: disconnect it from every host, reconnect and
rescan it, then disconnect it once more and forget it for good.
"""

from connection import connect


def manage_sr_lifecycle(url, username, password, nfs_server="192.0.2.10", nfs_path="/export/spare"):
    """Take a storage repository offline, bring it back, then forget it.

    There is no "detach" call on an SR. A shared SR is joined to each host by one PBD -- a
    physical block device -- and detaching the SR means unplugging every one of them. That
    is why an SR can be attached on some hosts and not others, and why a repair action
    exists at all: it plugs back the PBDs that are missing."""
    session = connect(url, username, password)
    x = session.xenapi

    host = x.host.get_all()[0]
    sr = x.SR.create(host, {"server": nfs_server, "serverpath": nfs_path, "nfsversion": "3"},
                     "0", "sdk-example-lifecycle", "SR used by the SDK lifecycle example",
                     "nfs", "user", True, {})
    pbds = x.SR.get_PBDs(sr)
    print("%s: connected on %d of %d host(s)"
          % (x.SR.get_name_label(sr), attached_pbds(x, pbds), len(pbds)))

    for pbd in pbds:
        x.PBD.unplug(pbd)
    print("  detached:   connected on %d host(s)" % attached_pbds(x, pbds))

    # Plugging them back is exactly what a repair does.
    for pbd in pbds:
        x.PBD.plug(pbd)
    print("  reattached: connected on %d host(s)" % attached_pbds(x, pbds))

    x.SR.scan(sr)
    print("  rescanned:  %d disk(s)" % len(x.SR.get_VDIs(sr)))

    # Forgetting drops the pool's record of the SR but leaves the storage itself untouched,
    # so the same export can be introduced again later. Detach before forgetting: a
    # connected SR is still in use.
    for pbd in pbds:
        x.PBD.unplug(pbd)
    x.SR.forget(sr)
    print("  forgotten")
    print("OK: manage-sr-lifecycle")
    session.logout()


def attached_pbds(x, pbds):
    """How many of these connections are currently live."""
    return sum(1 for pbd in pbds if x.PBD.get_currently_attached(pbd))
