"""Send logs to a remote syslog server.

Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the
setting is recorded but nothing changes.

Run it::

    configure_syslog("https://xenserver", "root", password)
"""

from connection import connect


def configure_syslog(url, username, password, syslog_server="192.0.2.50"):
    """Send a host's logs to a remote syslog server.

    Two steps, and the second is the one that is easy to miss: setting the destination only
    records it, and the host keeps logging locally until the syslog daemon is reconfigured to
    pick the setting up."""
    session = connect(url, username, password)
    x = session.xenapi
    host = x.pool.get_master(x.pool.get_all()[0])

    print("%s logging: %s" % (x.host.get_name_label(host), x.host.get_logging(host) or "(local only)"))

    x.host.remove_from_logging(host, "syslog_destination")
    x.host.add_to_logging(host, "syslog_destination", syslog_server)
    x.host.syslog_reconfigure(host)
    print("  now logging to: %s" % x.host.get_logging(host)["syslog_destination"])

    x.host.remove_from_logging(host, "syslog_destination")
    x.host.syslog_reconfigure(host)
    print("  restored: %s" % (x.host.get_logging(host) or "(local only)"))
    print("OK: configure-syslog")
    session.logout()
