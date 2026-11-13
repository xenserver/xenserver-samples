"""Create an NFS SR.

Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and
forget it.

Run it::

    create_nfs_sr("https://xenserver", "root", password, "192.0.2.10", "/export/sdk")
"""

from connection import connect
from helpers import detach_and_forget_sr


def create_nfs_sr(url, username, password, nfs_server, nfs_path, sr_name="sdk-example-nfs"):
    """Create a shared NFS SR, then forget it."""
    session = connect(url, username, password)
    host_ref = next(iter(session.xenapi.host.get_all_records().keys()))
    device_config = {"server": nfs_server, "serverpath": nfs_path, "nfsversion": "3"}

    sr_ref = session.xenapi.SR.create(
        host_ref, device_config, "0",
        sr_name, "NFS SR created by the SDK example",
        "nfs", "user", True, {})
    print("Created SR: %s" % session.xenapi.SR.get_uuid(sr_ref))

    detach_and_forget_sr(session, sr_ref)
    print("OK: create-nfs-sr")
    session.xenapi.session.logout()
