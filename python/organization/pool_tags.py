"""Tag the pool.

Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and
hosts.

Run it::

    pool_tags("https://xenserver", "root", password)
"""

from connection import connect


def pool_tags(url, username, password):
    """Add a tag to the pool, read it back, then remove it so the example is repeatable."""
    session = connect(url, username, password)
    pool_ref = session.xenapi.pool.get_all()[0]
    session.xenapi.pool.add_tags(pool_ref, "sdk-managed")
    print("Pool tags: %s" % ", ".join(session.xenapi.pool.get_tags(pool_ref)))
    session.xenapi.pool.remove_tags(pool_ref, "sdk-managed")
    print("OK: pool-tags")
    session.xenapi.session.logout()
