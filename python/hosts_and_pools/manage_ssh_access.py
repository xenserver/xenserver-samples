"""Manage SSH access.

Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it again
— the pool-level call fans out to every host.

Run it::

    manage_ssh_access("https://xenserver", "root", password)
"""

from connection import connect


def manage_ssh_access(url, username, password):
    """Turn the pool's SSH service on with an automatic cut-off, read it back, then turn it off.

    Timed access is the point: set the timeout first and the server stamps an ssh_expiry when SSH
    is enabled, so a window opened for troubleshooting closes itself. pool.set_ssh_enabled_timeout
    is itself a pool-wide fan-out call, exactly like enable_ssh/disable_ssh - no need to loop
    hosts for it either."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = list(x.pool.get_all())[0]
    # Each host's SSH as we found it, to put back at the end: disabling it is not the example's to keep.
    before = {h: (r["ssh_enabled"], r["ssh_enabled_timeout"]) for h, r in x.host.get_all_records().items()}

    x.pool.set_ssh_enabled_timeout(pool, str(3600))   # one hour

    # The pool call fans out to every host, so there is no need to loop for the enable itself.
    x.pool.enable_ssh(pool)
    for host in x.host.get_all():
        record = x.host.get_record(host)
        print("%s: ssh enabled=%s, expires %s"
              % (record["name_label"], record["ssh_enabled"], record["ssh_expiry"]))

    x.pool.disable_ssh(pool)
    print("After disable: %s"
          % ", ".join("%s=%s" % (h["name_label"], h["ssh_enabled"])
                      for h in x.host.get_all_records().values()))

    for host, (enabled, timeout) in before.items():
        x.host.set_ssh_enabled_timeout(host, timeout)   # first: enabling stamps the expiry from it
        if enabled:
            x.host.enable_ssh(host)
    print("OK: manage-ssh-access")
    session.logout()
