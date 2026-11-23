"""Point an SR at moved storage.

When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an SR
cannot be edited, so unplug each one, recreate it with the new settings and plug it back.

Run it::

    reconnect_sr_storage("https://xenserver", "root", password, "192.0.2.10", "/export/spare",
                         new_nfs_server="192.0.2.11")
"""

from connection import connect


def reconnect_sr_storage(url, username, password, nfs_server="192.0.2.10", nfs_path="/export/spare",
                         new_nfs_server=None):
    """Create an NFS SR on nfs_server:nfs_path, re-point it at new_nfs_server, then forget it.

    Each host reaches an SR through a PBD, whose device_config (server, path, target, ...) says where
    the storage is. A PBD's device_config is fixed when it is created, so changing it means unplugging
    the PBD, destroying it, and creating and plugging a new one with the updated settings, host by host.
    The SR and its disks are untouched throughout. Every PBD has to be unplugged first, which needs
    every VM using the SR to be shut down. new_nfs_server defaults to nfs_server, which reconnects
    the SR to the same storage."""
    session = connect(url, username, password)
    x = session.xenapi
    new_nfs_server = new_nfs_server or nfs_server

    host = x.host.get_all()[0]
    sr = x.SR.create(host, {"server": nfs_server, "serverpath": nfs_path, "nfsversion": "3"},
                     "0", "sdk-example-moved-storage", "SR used by the SDK reconnect example",
                     "nfs", "user", True, {})
    try:
        pbds = x.SR.get_PBDs(sr)
        for pbd in pbds:
            x.PBD.unplug(pbd)

        for pbd in pbds:
            record = x.PBD.get_record(pbd)
            device_config = dict(record["device_config"], server=new_nfs_server)
            x.PBD.destroy(pbd)
            pbd = x.PBD.create({"host": record["host"], "SR": sr, "device_config": device_config,
                                "other_config": {}})
            x.PBD.plug(pbd)
            print("%s: now reaches %s:%s" % (x.host.get_name_label(record["host"]),
                                             device_config["server"], device_config["serverpath"]))
    finally:
        # Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
        for pbd in x.SR.get_PBDs(sr):
            if x.PBD.get_currently_attached(pbd):
                x.PBD.unplug(pbd)
        x.SR.forget(sr)
    print("OK: reconnect-sr-storage")
    session.logout()
