"""Connecting to a pool: accept the host's self-signed certificate, log in, and follow HOST_IS_SLAVE
to the coordinator when given a pool member."""

import XenAPI


# --- connect ---
def connect(url, username, password):
    """Open a session, skipping certificate validation for the host's self-signed cert.

    If url points at a pool *member* rather than the coordinator, login fails with HOST_IS_SLAVE
    naming the coordinator's address; we reconnect to it (assuming the coordinator is up)."""
    session = XenAPI.Session(url, ignore_ssl=True)
    try:
        session.login_with_password(username, password, "1.0", "sdk-examples")
    except XenAPI.Failure as e:
        if e.details[0] != "HOST_IS_SLAVE":
            raise
        session = XenAPI.Session("https://%s" % e.details[1], ignore_ssl=True)  # the coordinator
        session.login_with_password(username, password, "1.0", "sdk-examples")
    return session
