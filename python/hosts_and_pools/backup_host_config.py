"""Back up a host's configuration.

Download a host's configuration backup and hand it back as a restore would — and watch another
host's backup be refused.
"""

import os
import shutil
import ssl
import tempfile
import time
import urllib.parse
import urllib.request

from connection import connect


def backup_host_config(url, username, password):
    """Download a host's configuration backup and offer it back, as a restore would.

    Both halves are HTTP transfers alongside the API rather than API calls, and the upload
    has a convention worth knowing: the server answers 200 as soon as it has read the
    request headers, because the client waits for that before it starts sending the file.
    The outcome therefore cannot be in the status line. It arrives on a task you create
    first, name in the URL, and poll once the upload has finished.

    Both halves are served only by whichever host physically accepted the HTTP connection - the
    handler ignores any ref= in the query string entirely, there is no forwarding to another pool
    member. So backing up/restoring a host means opening the connection to THAT host's own
    address, not to the pool's (coordinator) url - a restore sent to the wrong host's connection
    silently restores the WRONG host, not the one named by ref=. ref= is kept in the query string
    purely for log-readability (a real host ignores it; it is not what makes this correct)."""
    session = connect(url, username, password)
    x = session.xenapi
    ctx = ssl._create_unverified_context()

    # The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
    host = x.pool.get_master(x.pool.get_all()[0])
    hosts = [host] + [h for h in x.host.get_all() if h != host]
    host_url = _host_url(url, x.host.get_address(host))
    print("Backing up %s" % x.host.get_name_label(host))

    path = os.path.join(tempfile.gettempdir(), "sdk-example-host.backup")
    with urllib.request.urlopen(
            "%s/host_backup?session_id=%s&ref=%s" % (host_url, session._session, host),
            context=ctx, timeout=1800) as response, open(path, "wb") as out:   # the host packs it first
        shutil.copyfileobj(response, out)       # hundreds of MB: stream it, don't hold it in memory
    print("  wrote %d bytes to %s" % (os.path.getsize(path), os.path.basename(path)))
    _drop_idle_connection(session)

    print("  restoring it to %s: %s"
          % (x.host.get_name_label(host), restore_host_config(session, ctx, host_url, host, path)))

    if len(hosts) > 1:
        other = hosts[1]
        other_url = _host_url(url, x.host.get_address(other))
        try:
            result = restore_host_config(session, ctx, other_url, other, path)
        except Exception as e:
            # A real pool's hosts are all reachable from a management client; this only guards an
            # environment (a host whose address isn't routable from here, say) where that isn't
            # true, so the example still finishes cleanly.
            result = "could not connect to %s directly (%s)" % (other_url, e)
        print("  restoring it to %s: %s" % (x.host.get_name_label(other), result))

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
    """Upload a backup to a host - over a connection opened to THAT host's own address - and
    report what the task says about it."""
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
        if x.task.get_status(task) == "success":
            return "accepted"
        return "refused (%s)" % x.task.get_error_info(task)[-1]
    finally:
        x.task.destroy(task)
