"""Configure host storage.

Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.

Run it::

    configure_host_storage("https://xenserver", "root", password)
"""

from connection import connect


def configure_host_storage(url, username, password):
    """Set a host's iSCSI initiator name and turn on storage multipathing.

    The IQN identifies this host to iSCSI targets, so a target's access list is written
    against it -- changing it on a host with live iSCSI storage cuts it off. Multipathing uses
    every path to the storage rather than one, and on real hardware you put the host into
    maintenance mode before changing it, because the paths are rebuilt."""
    session = connect(url, username, password)
    x = session.xenapi
    host = x.pool.get_master(x.pool.get_all()[0])

    before_iqn = x.host.get_iscsi_iqn(host)
    before_multipathing = x.host.get_multipathing(host)
    print("%s: iSCSI IQN %r, multipathing %s"
          % (x.host.get_name_label(host), before_iqn, before_multipathing))

    x.host.set_iscsi_iqn(host, "iqn.2026-01.com.example:%s" % x.host.get_name_label(host))
    x.host.set_multipathing(host, True)
    print("  IQN now:      %s" % x.host.get_iscsi_iqn(host))
    print("  multipathing: %s" % x.host.get_multipathing(host))

    # set_iscsi_iqn refuses an empty string (INVALID_VALUE); only restore it if this host actually
    # had one set before - a host that has never had an IQN configured has it empty, and there is
    # no way to set it back to empty through this call.
    if before_iqn:
        x.host.set_iscsi_iqn(host, before_iqn)
    x.host.set_multipathing(host, before_multipathing)
    print("  restored")
    print("OK: configure-host-storage")
    session.logout()
