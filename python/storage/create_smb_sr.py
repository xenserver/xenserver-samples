"""Create an SMB SR.

Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
credentials (the password as a secret, never in plain text).
"""

from connection import connect
from helpers import detach_and_forget_sr


def create_smb_sr(url, username, password, server, share, smb_username, smb_password,
                   sr_name="sdk-example-smb"):
    """Connect a shared SR to an SMB/CIFS file share (create validates + sizes from the share).

    The password travels as a Secret, not plaintext device-config - the way XenCenter does
    it."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    host = session.xenapi.host.get_all()[0]

    secret = session.xenapi.secret.create({"value": smb_password, "other_config": {}})
    # server is the share as one UNC path, //server/share: the SMB driver has no separate serverpath.
    dc = {"server": "//%s%s" % (server, share), "username": smb_username,
          "password_secret": session.xenapi.secret.get_uuid(secret)}
    sr = session.xenapi.SR.create(host, dc, "0", sr_name,
                                  "SMB SR created by the SDK example", "smb", "user", True, {})
    print("Created SR: %s (%d GiB)"
          % (session.xenapi.SR.get_uuid(sr), int(session.xenapi.SR.get_physical_size(sr)) // GIB))
    detach_and_forget_sr(session, sr)
    session.xenapi.secret.destroy(secret)
    print("OK: create-smb-sr")
    session.logout()
