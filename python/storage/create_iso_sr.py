"""Create an ISO library SR.

Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so the
images are available as installation media.
"""

from connection import connect
from helpers import detach_and_forget_sr


def create_iso_sr(url, username, password, location):
    """Connect an ISO-library SR to a file share of ISO images (here an NFS export, location
    "server:/path")."""
    session = connect(url, username, password)
    host = session.xenapi.host.get_all()[0]
    dc = {"location": location, "type": "nfs_iso"}
    sr = session.xenapi.SR.create(host, dc, "0", "sdk-example-iso",
                                  "ISO library created by the SDK example", "iso", "iso", True, {})
    print("Created ISO SR: %s" % session.xenapi.SR.get_uuid(sr))
    detach_and_forget_sr(session, sr)
    print("OK: create-iso-sr")
    session.logout()
