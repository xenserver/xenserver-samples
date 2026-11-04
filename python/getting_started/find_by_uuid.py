"""Look up an object by UUID.

Resolve a stable UUID back to a live object reference — how to persist a reference to an object
across sessions.

Run it::

    find_by_uuid("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def find_by_uuid(url, username, password, vm_name):
    """Resolve a VM's UUID back to a (session-scoped) ref, as persisted identifiers do."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    uuid = session.xenapi.VM.get_uuid(vm)
    resolved = session.xenapi.VM.get_by_uuid(uuid)
    print("UUID %s resolves to %s" % (uuid, session.xenapi.VM.get_name_label(resolved)))
    print("Same object: %s" % (resolved == vm))
    print("OK: find-by-uuid")
    session.xenapi.session.logout()
