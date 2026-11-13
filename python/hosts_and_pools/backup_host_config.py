"""Back up a host's configuration.

Download a host's configuration backup and verify it downloaded; optionally stage it back onto that
same host's backup partition, ready for a restore done from the installer.
"""

import os
import shutil
import ssl
import tempfile
import time
import urllib.parse
import urllib.request

from connection import connect


def backup_host_config(url, username, password, restore=False):
    """Download a host's configuration backup and verify it, then optionally stage it back as a restore.

    Both halves are HTTP transfers alongside the API rather than API calls, and the upload
    has a convention worth knowing: the server answers 200 as soon as it has read the
    request headers, because the client waits for that before it starts sending the file.
    The outcome therefore cannot be in the status line. It arrives on a task you create
    first, name in the URL, and poll once the upload has finished.

    Both halves are served only by whichever host physically accepted the HTTP connection - the
    handler ignores any ref= in the query string entirely, there is no forwarding to another pool
    member. So backing up/restoring a host means opening the connection to THAT host's own
    address, not to the pool's (coordinator) url. ref= is kept in the query string purely for
    log-readability (a real host ignores it).

    restore=True stages the backup onto the SAME host's backup partition (restore=true from the
    command line, or the Python bool). host-restore does not restore the host there and then: it only
    writes the archive over that host's currently inactive backup partition, ready for the next boot.
    It takes effect only once that host is booted from the installer and Restore is chosen there."""
    if isinstance(restore, str):  # from the command line
        restore = restore.lower() == "true"
    session = connect(url, username, password)
    x = session.xenapi
    ctx = ssl._create_unverified_context()

    # The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
    host = x.pool.get_master(x.pool.get_all()[0])
    host_url = _host_url(url, x.host.get_address(host))
    print("Backing up %s" % x.host.get_name_label(host))

    path = os.path.join(tempfile.gettempdir(), "sdk-example-host.backup")
    with urllib.request.urlopen(
            "%s/host_backup?session_id=%s&ref=%s" % (host_url, session._session, host),
            context=ctx, timeout=1800) as response, open(path, "wb") as out:   # the host packs it first
        shutil.copyfileobj(response, out)       # hundreds of MB: stream it, don't hold it in memory
    size = os.path.getsize(path)
    if size == 0:
        raise RuntimeError("%s came back empty" % path)
    print("  wrote %d bytes to %s" % (size, os.path.basename(path)))
    _drop_idle_connection(session)

    name = x.host.get_name_label(host)
    if restore:
        restore_host_config(session, ctx, host_url, host, path)
        print("  staged it on %s's backup partition - it takes effect only after booting that host "
              "from the installer and choosing Restore" % name)
    else:
        print("  not restoring it (pass restore=true to stage it on %s's backup partition)" % name)

    os.remove(path)
    print("OK: backup-host-config")
    session.logout()


def _host_url(url, address):
    """Build the URL for a given host's own address, keeping the scheme and port the caller
    originally connected with (a host's management address carries no port of its own)."""
    parts = urllib.parse.urlsplit(url)
    port = ":%d" % parts.port if parts.port else ""
    return "%s://%s%s" % (parts.scheme, address, port)


def _drop_idle_connection(session):
    """Close the session's HTTP connection after a long transfer; the next call opens a new one.
    The session itself is still valid - but its one keep-alive connection sat idle for as long as
    the transfer took, and a network that dropped it meanwhile leaves the next call hanging until
    the socket times out. (ServerProxy("close")() is xmlrpc.client's way to close its transport.)"""
    session("close")()


def restore_host_config(session, ctx, host_url, host, path):
    """Upload a backup to a host - over a connection opened to THAT host's own address - and raise
    if the task reports it was refused."""
    x = session.xenapi
    task = x.task.create("host_restore", "restoring a configuration backup")
    try:
        with open(path, "rb") as f:
            request = urllib.request.Request(
                "%s/host_restore?session_id=%s&ref=%s&task_id=%s" % (host_url, session._session, host, task),
                data=f, headers={"Content-Length": str(os.path.getsize(path))}, method="PUT")
            # The timeout covers each socket operation, including waiting for the host's answer once the
            # whole backup (hundreds of MB) has arrived - a real host takes far longer than seconds.
            urllib.request.urlopen(request, context=ctx, timeout=1800).read()
        _drop_idle_connection(session)

        while x.task.get_status(task) == "pending":
            time.sleep(0.5)
        if x.task.get_status(task) != "success":
            raise RuntimeError("refused (%s)" % x.task.get_error_info(task)[-1])
    finally:
        x.task.destroy(task)
