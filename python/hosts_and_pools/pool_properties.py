"""Pool properties.

Read the pool name and default storage repository, then rename the pool and restore it.

Run it::

    pool_properties("https://xenserver", "root", password)
"""

from connection import connect


def pool_properties(url, username, password):
    """Read the pool's name and default SR, rename the pool, then restore the name."""
    session = connect(url, username, password)
    pool_ref = session.xenapi.pool.get_all()[0]
    original = session.xenapi.pool.get_name_label(pool_ref)
    default_sr = session.xenapi.pool.get_default_SR(pool_ref)
    print("Pool:       '%s'" % original)
    print("Default SR: %s"
          % ("(none)" if default_sr == "OpaqueRef:NULL"
             else session.xenapi.SR.get_name_label(default_sr)))

    session.xenapi.pool.set_name_label(pool_ref, "sdk-pool-renamed")
    print("Renamed to: '%s'" % session.xenapi.pool.get_name_label(pool_ref))
    session.xenapi.pool.set_name_label(pool_ref, original)  # restore
    print("OK: pool-properties")
    session.xenapi.session.logout()
