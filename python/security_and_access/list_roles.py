"""List RBAC roles.

Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to
users.

Run it::

    list_roles("https://xenserver", "root", password)
"""

from connection import connect


def list_roles(url, username, password):
    """List the RBAC roles."""
    session = connect(url, username, password)
    # Note the class is lowercase 'role' in the binding. Role records include every permission too; the
    # roles a user can be granted are the ones made of permissions (non-empty subroles), as xe role-list shows.
    roles = sorted({r["name_label"] for r in session.xenapi.role.get_all_records().values() if r["subroles"]})
    print("Roles (%d): %s" % (len(roles), ", ".join(roles[:8])))
    print("OK: list-roles")
    session.xenapi.session.logout()
